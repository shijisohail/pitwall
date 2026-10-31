import Testing
import Foundation
@testable import Pitwall

/// Runs the real `ClaudeRunner`/`Conversation` against a fake CLI that speaks the stream-json protocol.
/// Serialized, and it owns every test that changes the process-wide CLI path.
@MainActor @Suite(.serialized) struct RunnerIntegrationTests {
    private func make() -> (Store, Conversation) {
        let s = makeStore()
        let c = Conversation(cwd: NSTemporaryDirectory()); c.store = s
        s.conversations.append(c)
        return (s, c)
    }
    private func lastAssistantText(_ c: Conversation) -> String {
        c.messages.last { $0.role == .assistant }?.blocks.compactMap { $0.kind == .text ? $0.text : nil }.joined() ?? ""
    }

    @Test func controlRequestsRoundTrip() async {
        await withFakeClaude {
            let r = ClaudeRunner()
            #expect((try? r.start(.init(cwd: NSTemporaryDirectory()))) != nil)
            var body: [String: Any]?
            r.request("initialize") { body = $0 }
            #expect(await waitUntil { body != nil })
            let cat = Catalog(body ?? [:])
            #expect(cat.commands.first?.name == "fake-cmd"); #expect(cat.version == "0.0.0-fake")
            r.stop()
        }
    }

    @Test func aPromptStreamsAReplyAndRecordsSessionAndCost() async {
        await withFakeClaude {
            let (_, c) = make()
            c.send("hi")
            #expect(await waitUntil { !c.isRunning && self.lastAssistantText(c) == "hello from fake" })
            #expect(c.sessionID == "fake-session-1"); #expect(c.modelName == "fake-model"); #expect(c.cost == 0.02)
            c.teardown()
        }
    }

    @Test func approvingAToolSendsAllowOverTheWire() async {
        await withFakeClaude {
            let (_, c) = make(); c.permission = .manual
            c.send("please approve this")
            #expect(await waitUntil { !c.approvals.isEmpty })
            guard let a = c.approvals.first else { c.teardown(); return }
            #expect(a.tool == "Write")
            c.allow(a)
            #expect(await waitUntil { !c.isRunning && self.lastAssistantText(c) == "allowed" })
            c.teardown()
        }
    }

    @Test func denyingAToolSendsDenyOverTheWire() async {
        await withFakeClaude {
            let (_, c) = make(); c.permission = .manual
            c.send("please approve this")
            #expect(await waitUntil { !c.approvals.isEmpty })
            guard let a = c.approvals.first else { c.teardown(); return }
            c.deny(a, message: "no thanks")
            #expect(await waitUntil { !c.isRunning && self.lastAssistantText(c) == "denied" })
            c.teardown()
        }
    }

    @Test func stopInterruptsAHungTurnAndTheSessionStaysUsable() async {
        await withFakeClaude {
            let (_, c) = make()
            c.send("hang")
            #expect(await waitUntil { c.isRunning && c.runner != nil })
            try? await Task.sleep(for: .milliseconds(300))
            c.stop()
            #expect(await waitUntil(5) { !c.isRunning })
            #expect(c.messages.contains { $0.blocks.contains { $0.kind == .notice && $0.text == "Stopped" } })
            #expect(!c.messages.contains { $0.blocks.contains { $0.kind == .error } })
            c.send("hi again")
            #expect(await waitUntil { !c.isRunning && self.lastAssistantText(c) == "hello from fake" })
            c.teardown()
        }
    }

    @Test func aMissingCLIReportsAnErrorInsteadOfCrashing() {
        let saved = (ClaudeRunner.pathOverride, ClaudeRunner.discoveryEnabled)
        defer { (ClaudeRunner.pathOverride, ClaudeRunner.discoveryEnabled) = saved }
        ClaudeRunner.pathOverride = nil; ClaudeRunner.discoveryEnabled = false
        let (_, c) = make()
        c.send("hi")
        #expect(c.messages.last?.blocks.first?.kind == .error)
        #expect(c.messages.last?.blocks.first?.text.contains("claude") == true)
        #expect(!c.isRunning)
    }

    @Test func aChosenClaudePathIsUsedOnlyIfItIsExecutable() {
        let saved = (ClaudeRunner.pathOverride, ClaudeRunner.discoveryEnabled)
        defer { (ClaudeRunner.pathOverride, ClaudeRunner.discoveryEnabled) = saved }
        ClaudeRunner.discoveryEnabled = false
        ClaudeRunner.pathOverride = "/definitely/not/here"
        #expect(ClaudeRunner.claudePath == nil)
        ClaudeRunner.pathOverride = "/bin/ls"
        #expect(ClaudeRunner.claudePath == "/bin/ls")
        ClaudeRunner.pathOverride = "/etc/hosts"                          // exists but isn't executable
        #expect(ClaudeRunner.claudePath == nil)
    }

    // MARK: Message queue

    private func result(sub: String = "success", isError: Bool = false) -> [String: Any] {
        ["type": "result", "subtype": sub, "is_error": isError, "result": "", "session_id": "s1"]
    }

    @Test func aQueuedMessageIsSentWhenTheTurnFinishes() async {
        await withFakeClaude {
            let (_, c) = make()
            c.isRunning = true
            #expect(c.enqueue("  second  "))
            #expect(c.queue.count == 1 && c.queue[0].text == "second")
            c.handle(result())
            #expect(c.queue.isEmpty)
            #expect(c.messages.first?.role == .user && c.messages.first?.blocks.first?.text == "second")
            #expect(await waitUntil { !c.isRunning && self.lastAssistantText(c) == "hello from fake" })
            c.teardown()
        }
    }

    @Test func queuedMessagesGoOutOneAtATime() async {
        await withFakeClaude {
            let (_, c) = make()
            c.isRunning = true
            c.enqueue("one"); c.enqueue("two")
            c.handle(result())
            #expect(c.queue.map(\.text) == ["two"])                          // "one" is running; "two" waits its turn
            #expect(await waitUntil { c.queue.isEmpty && !c.isRunning })      // finishing "one" releases "two"
            let sent = c.messages.filter { $0.role == .user }.compactMap { $0.blocks.first?.text }
            #expect(sent == ["one", "two"])
            c.teardown()
        }
    }

    @Test func anErrorOrStopLeavesTheQueueAlone() {
        let (_, c) = make()
        c.isRunning = true; c.enqueue("later")
        c.handle(result(sub: "error_during_execution", isError: true))
        #expect(c.queue.count == 1)
        #expect(!c.messages.contains { $0.role == .user })
    }

    @Test func stoppingHandsTheQueueBackToTheComposer() {
        let (_, c) = make()
        c.isRunning = true
        c.enqueue("a"); c.enqueue("b")
        c.stop()
        #expect(c.queue.isEmpty)
        #expect(c.draftAppend == ["a", "b"])
        c.isRunning = false
    }

    @Test func editingAQueuedMessagePullsItBack() {
        let (_, c) = make()
        c.isRunning = true
        c.enqueue("fix typo"); c.enqueue("second")
        c.editQueued(c.queue[0].id)
        #expect(c.queue.map(\.text) == ["second"]); #expect(c.draftAppend == ["fix typo"])
        c.unqueue(c.queue[0].id)
        #expect(c.queue.isEmpty)
        c.isRunning = false
    }

    @Test func emptyMessagesAreNotQueued() {
        let (_, c) = make()
        #expect(!c.enqueue("   \n "))
        #expect(c.queue.isEmpty)
    }
}
