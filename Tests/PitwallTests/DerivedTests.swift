import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite struct DerivedTests {
    private func tool(_ name: String, _ input: [String: Any], result: String? = "ok", isError: Bool = false) -> Block {
        var b = Block(kind: .tool); b.toolName = name; b.toolID = UUID().uuidString
        b.inputJSON = String(decoding: try! JSONSerialization.data(withJSONObject: input), as: UTF8.self)
        b.result = result; b.isError = isError
        return b
    }
    private func conv(_ blocks: [Block]) -> Conversation {
        let c = Conversation(cwd: "/w"); c.messages = [ChatMessage(role: .assistant, blocks: blocks)]; return c
    }

    @Test func onlyAppliedEditsCount() {
        let c = conv([
            tool("Edit", ["file_path": "/w/a.swift", "old_string": "a\nb", "new_string": "a\nb\nc"]),
            tool("Edit", ["file_path": "/w/denied.swift", "old_string": "x", "new_string": "y"], isError: true),
            tool("Edit", ["file_path": "/w/pending.swift", "old_string": "x", "new_string": "y"], result: nil),
            tool("Write", ["file_path": "/w/new.txt", "content": "1\n2\n3"]),
        ])
        let ch = c.fileChanges()
        #expect(ch.map(\.path) == ["/w/a.swift", "/w/new.txt"])
        #expect(ch[0].added == 3 && ch[0].removed == 2)
        #expect(ch[1].isNew && ch[1].added == 3)
        #expect(c.diffStat.files == 2)
    }

    @Test func multiEditAndRepeatedEditsAccumulatePerFile() {
        let c = conv([
            tool("MultiEdit", ["file_path": "/w/a.swift", "edits": [["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d\ne"]]]),
            tool("Edit", ["file_path": "/w/a.swift", "old_string": "z", "new_string": "y"]),
        ])
        let ch = c.fileChanges()
        #expect(ch.count == 1); #expect(ch[0].hunks.count == 3); #expect(ch[0].added == 4); #expect(ch[0].removed == 3)
    }

    @Test func todoProgressAndPlanComeFromTheLatestCalls() {
        let c = conv([
            tool("TodoWrite", ["todos": [["content": "old", "status": "pending"]]]),
            tool("TodoWrite", ["todos": [["content": "a", "status": "completed"], ["content": "b", "status": "in_progress"]]]),
            tool("ExitPlanMode", ["plan": "# Do the thing"]),
        ])
        #expect(c.todoProgress?.done == 1); #expect(c.todoProgress?.total == 2)
        #expect(c.latestPlan == "# Do the thing")
    }

    @Test func feedShowsTheLastThreeStepsWithTheirState() {
        let c = conv((0..<5).map { tool("Read", ["file_path": "/w/\($0).swift"], result: $0 == 4 ? nil : "ok") })
        c.isRunning = true
        let f = c.feed
        #expect(f.count == 3)
        #expect(f.last?.state == .running); #expect(f.first?.state == .done)
    }

    @Test func emptyConversationsProduceNothing() {
        let c = Conversation(cwd: "/w")
        #expect(c.fileChanges().isEmpty); #expect(c.feed.isEmpty); #expect(c.todoProgress == nil); #expect(c.latestPlan == nil)
    }
}
