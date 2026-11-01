import Testing
import Foundation
@testable import Pitwall

/// The wording of the running-session status bar.
@MainActor @Suite struct ActivityTests {
    private func make() -> Conversation {
        let s = makeStore(); let c = Conversation(cwd: "/tmp"); c.store = s; s.conversations.append(c); return c
    }
    private func tool(_ name: String, _ json: String, result: String? = nil) -> Block {
        var b = Block(kind: .tool); b.toolName = name; b.inputJSON = json; b.result = result; return b
    }

    @Test func aTurnThatHasNotStartedRepliedYetIsThinking() {
        let c = make(); c.isRunning = true
        #expect(c.activityText == "Thinking…")
        c.messages = [ChatMessage(role: .user, blocks: [Block(kind: .text, text: "hi")])]
        #expect(c.activityText == "Thinking…")
    }

    @Test func itNamesTheToolThatIsRunning() {
        let c = make(); c.isRunning = true
        func set(_ b: Block) { c.messages = [ChatMessage(role: .assistant, blocks: [b])] }
        set(tool("Read", #"{"file_path":"/Users/x/Sources/Composer.swift"}"#)); #expect(c.activityText == "Reading Composer.swift")
        set(tool("Edit", #"{"file_path":"/a/b/Agents.swift"}"#)); #expect(c.activityText == "Editing Agents.swift")
        set(tool("Bash", #"{"command":"swift test","description":"Run the tests"}"#)); #expect(c.activityText == "Run the tests")
        set(tool("Bash", #"{"command":"swift test"}"#)); #expect(c.activityText == "Running swift test")
        set(tool("Grep", #"{"pattern":"showAgents"}"#)); #expect(c.activityText == "Searching showAgents")
        set(tool("WebFetch", #"{"url":"https://example.com"}"#)); #expect(c.activityText == "Fetching https://example.com")
        set(tool("Agent", #"{"description":"review docs"}"#)); #expect(c.activityText == "Agent: review docs")
        set(tool("TodoWrite", #"{"todos":[]}"#)); #expect(c.activityText == "Planning…")
    }

    @Test func finishedToolsAreSkippedAndTheTextFallsBackToWhatIsStreaming() {
        let c = make(); c.isRunning = true
        c.messages = [ChatMessage(role: .assistant, blocks: [tool("Read", #"{"file_path":"/a.swift"}"#, result: "ok"), Block(kind: .thinking)])]
        #expect(c.activityText == "Thinking…")
        c.messages = [ChatMessage(role: .assistant, blocks: [tool("Read", #"{"file_path":"/a.swift"}"#, result: "ok"), Block(kind: .text, text: "Here")])]
        #expect(c.activityText == "Writing…")
    }

    @Test func waitingForApprovalWinsAndLongCommandsAreShortened() {
        let c = make(); c.isRunning = true
        c.messages = [ChatMessage(role: .assistant, blocks: [tool("Bash", "{\"command\":\"\(String(repeating: "x", count: 200))\"}")])]
        #expect(c.activityText.count < 90)
        c.approvals = [Approval(id: "1", kind: .tool, tool: "Bash", input: [:], detail: nil, reason: nil, suggestions: [])]
        #expect(c.activityText == "Waiting for your approval")
    }
}
