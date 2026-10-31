import Testing
import Foundation
@testable import Pitwall

/// Runs the real `ClaudeRunner`/`Conversation` against a fake CLI that speaks the stream-json protocol.
/// Serialized: they swap the process-wide CLI path.
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

    @Test func controlRequestsRoundTrip() {
        withFakeClaude {
            let r = ClaudeRunner()
            #expect((try? r.start(.init(cwd: NSTemporaryDirectory()))) != nil)
            var body: [String: Any]?
            r.request("initialize") { body = $0 }
            #expect(waitUntil { body != nil })
            let cat = Catalog(body ?? [:])
            #expect(cat.commands.first?.name == "fake-cmd"); #expect(cat.version == "0.0.0-fake")
            r.stop()
        }
    }

    @Test func aPromptStreamsAReplyAndRecordsSessionAndCost() {
        withFakeClaude {
            let (_, c) = make()
            c.send("hi")
            #expect(waitUntil { !c.isRunning && self.lastAssistantText(c) == "hello from fake" })
            #expect(c.sessionID == "fake-session-1"); #expect(c.modelName == "fake-model"); #expect(c.cost == 0.02)
            c.teardown()
        }
    }

    @Test func approvingAToolSendsAllowOverTheWire() {
        withFakeClaude {
            let (_, c) = make(); c.permission = .manual
            c.send("please approve this")
            #expect(waitUntil { !c.approvals.isEmpty })
            #expect(c.approvals.first?.tool == "Write")
            c.allow(c.approvals[0])
            #expect(waitUntil { !c.isRunning && self.lastAssistantText(c) == "allowed" })
            c.teardown()
        }
    }

    @Test func denyingAToolSendsDenyOverTheWire() {
        withFakeClaude {
            let (_, c) = make(); c.permission = .manual
            c.send("please approve this")
            #expect(waitUntil { !c.approvals.isEmpty })
            c.deny(c.approvals[0], message: "no thanks")
            #expect(waitUntil { !c.isRunning && self.lastAssistantText(c) == "denied" })
            c.teardown()
        }
    }

    @Test func stopInterruptsAHungTurnAndTheSessionStaysUsable() {
        withFakeClaude {
            let (_, c) = make()
            c.send("hang")
            #expect(waitUntil { c.isRunning && c.runner != nil })
            Thread.sleep(forTimeInterval: 0.3)
            c.stop()
            #expect(waitUntil(5) { !c.isRunning })
            #expect(c.messages.contains { $0.blocks.contains { $0.kind == .notice && $0.text == "Stopped" } })
            #expect(!c.messages.contains { $0.blocks.contains { $0.kind == .error } })
            c.send("hi again")
            #expect(waitUntil { !c.isRunning && self.lastAssistantText(c) == "hello from fake" })
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
}
