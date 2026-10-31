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
}
