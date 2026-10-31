import Testing
import Foundation
@testable import Pitwall

/// Agent tracking, driven by a real captured stream (see AgentsFixture.swift) and by hand-built events.
/// Serialized: the tests flip the shared `AppSettings.shared.showAgents`, and a test that awaits would otherwise
/// see another test's value mid-run.
@MainActor @Suite(.serialized) struct AgentTrackingTests {
    /// The Agent view is off by default, so tests that exercise tracking switch it on first.
    private func make(agentsOn: Bool = true) -> Conversation {
        AppSettings.shared.showAgents = agentsOn
        let s = makeStore()
        let c = Conversation(cwd: "/tmp"); c.store = s
        s.conversations.append(c)
        return c
    }

    @Test func aRealStreamSpawnsTracksAndFinishesThreeAgents() {
        let c = make()
        var sawThreeWorking = false
        for e in agentsFixtureEvents() {
            c.handle(e)
            if c.agents.count == 3, c.agents.allSatisfy({ !$0.state.isFinished }) { sawThreeWorking = true }
        }
        #expect(sawThreeWorking)
        #expect(c.agents.count == 3)
        #expect(Set(c.agents.map(\.name)) == ["count-files", "say-ok", "bg-ok"])
        #expect(c.agents.allSatisfy { $0.state == .done && $0.zone == .rest && $0.endedAt != nil })
        #expect(c.agentsWorking == 0)
        let files = c.agents.first { $0.name == "count-files" }!
        #expect(files.type == "general-purpose" && files.background && files.depth == 1 && files.parentID == nil)
        #expect(files.toolUses >= 1 && files.tokens > 0)
        #expect(files.steps.contains { $0.kind == .run && $0.title == "Bash" && $0.state == .done })
        #expect(c.agents.first { $0.name == "bg-ok" }?.report == "DONE")
    }

    @Test func settingOffTracksNothing() {
        let c = make(agentsOn: false)
        agentsFixtureEvents().forEach(c.handle)
        #expect(c.agents.isEmpty)
    }

    @Test func theAgentViewIsOffByDefault() {
        let fresh = AppSettings(defaults: UserDefaults(suiteName: "agents-default-\(UUID().uuidString)")!)
        #expect(fresh.showAgents == false)
    }

    @Test func aChosenSettingIsRemembered() {
        let suite = "agents-remember-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        AppSettings(defaults: d).showAgents = true
        #expect(AppSettings(defaults: d).showAgents == true)
    }

    @Test func switchingTheViewOffClearsAgentsAndOnRebuildsThemFromHistory() async {
        let c = make()
        var launch = Block(kind: .tool); launch.toolName = "Agent"; launch.toolID = "tu1"; launch.inputJSON = #"{"description":"docs"}"#; launch.result = "done"
        c.messages = [ChatMessage(role: .assistant, blocks: [launch])]
        c.seedAgentsFromHistory()
        #expect(c.agents.count == 1)
        AppSettings.shared.showAgents = false                       // the store clears every session's agents
        #expect(await waitUntil { c.agents.isEmpty })
        agentsFixtureEvents().forEach(c.handle)
        #expect(c.agents.isEmpty)                                   // and nothing is tracked while it is off
        AppSettings.shared.showAgents = true                        // back on: finished agents return from the transcript
        #expect(await waitUntil { c.agents.map(\.id) == ["tu1"] })
        AppSettings.shared.showAgents = false
    }

    @Test func nestedAgentsRecordTheirParent() {
        let c = make()
        c.handle(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "outer", "name": "Agent", "input": ["description": "outer", "prompt": "p"]]]]])
        c.handle(["type": "system", "subtype": "task_started", "task_id": "t1", "tool_use_id": "outer", "description": "outer", "subagent_type": "general-purpose", "spawn_depth": 1])
        c.handle(["type": "assistant", "parent_tool_use_id": "outer", "message": ["content": [["type": "tool_use", "id": "inner", "name": "Task", "input": ["description": "inner", "subagent_type": "Explore"]]]]])
        let inner = c.agents.first { $0.id == "inner" }
        #expect(inner?.parentID == "outer" && inner?.type == "Explore")
        #expect(c.agents.first { $0.id == "outer" }?.steps.last?.kind == .agent)     // the outer agent is delegating
    }

    @Test func stepsFollowToolCallsAndMoveTheBotBetweenZones() {
        let c = make()
        c.handle(["type": "system", "subtype": "task_started", "task_id": "t", "tool_use_id": "a", "description": "a", "subagent_type": "x", "spawn_depth": 1])
        func step(_ name: String, _ id: String, _ input: [String: Any]) {
            c.handle(["type": "assistant", "parent_tool_use_id": "a", "message": ["content": [["type": "tool_use", "id": id, "name": name, "input": input]]]])
        }
        step("Read", "r1", ["file_path": "/x/Composer.swift"]); #expect(c.agents[0].zone == .read)
        c.handle(["type": "user", "parent_tool_use_id": "a", "message": ["content": [["type": "tool_result", "tool_use_id": "r1", "content": "ok"]]]])
        #expect(c.agents[0].steps[0].state == .done && c.agents[0].zone == .think)
        step("Edit", "e1", ["file_path": "/x/a.swift"]); #expect(c.agents[0].zone == .edit)
        step("Bash", "b1", ["command": "swift test"]); #expect(c.agents[0].zone == .run)
        c.handle(["type": "system", "subtype": "task_notification", "tool_use_id": "a", "status": "failed", "summary": "boom", "usage": ["total_tokens": 5, "tool_uses": 3, "duration_ms": 900]])
        #expect(c.agents[0].state == .failed && c.agents[0].zone == .rest && c.agents[0].report == "boom")
        #expect(c.agents[0].steps.allSatisfy { $0.state != .running })
    }

    @Test func aForegroundAgentFinishesFromItsToolResultButAnAsyncLaunchDoesNot() {
        let c = make()
        func spawn(_ id: String) { c.handle(["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": "Agent", "input": ["description": id]]]]]) }
        func result(_ id: String, _ text: String) { c.handle(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": text]]]]) }
        spawn("async"); result("async", "Async agent launched successfully. agentId: x")
        spawn("sync"); result("sync", "Found 3 files.")
        #expect(c.agents.first { $0.id == "async" }?.state == .starting)
        let sync = c.agents.first { $0.id == "sync" }
        #expect(sync?.state == .done && sync?.report == "Found 3 files.")
    }

    @Test func reopenedSessionsSeedFinishedAgentsFromTheirTranscript() {
        let c = make()
        var launch = Block(kind: .tool); launch.toolName = "Agent"; launch.toolID = "tu1"
        launch.inputJSON = #"{"description":"review docs","subagent_type":"Explore","prompt":"look"}"#
        launch.result = "Async agent launched successfully."
        var sync = Block(kind: .tool); sync.toolName = "Agent"; sync.toolID = "tu2"; sync.inputJSON = #"{"description":"quick"}"#; sync.result = "all good"
        var lost = Block(kind: .tool); lost.toolName = "Agent"; lost.toolID = "tu3"; lost.inputJSON = #"{"description":"orphan"}"#; lost.result = "Async agent launched successfully."
        let note = "<task-notification><task-id>x</task-id><tool-use-id>tu1</tool-use-id><status>completed</status><usage><subagent_tokens>2000</subagent_tokens><tool_uses>4</tool_uses><duration_ms>9000</duration_ms></usage></task-notification>"
        c.messages = [ChatMessage(role: .assistant, blocks: [launch, sync, lost]), ChatMessage(role: .user, blocks: [Block(kind: .text, text: note)])]
        c.seedAgentsFromHistory()
        #expect(c.agents.count == 3)
        let a = c.agents.first { $0.id == "tu1" }!
        #expect(a.state == .done && a.type == "Explore" && a.tokens == 2000 && a.toolUses == 4 && a.durationMS == 9000)
        #expect(c.agents.first { $0.id == "tu2" }?.report == "all good")
        #expect(c.agents.first { $0.id == "tu3" }?.state == .stopped)
        c.seedAgentsFromHistory()                                   // idempotent: re-running (the tail does) adds nothing
        #expect(c.agents.count == 3)
    }

    @Test func stepsAreCapped() {
        var r = AgentRun(id: "a", name: "a")
        for i in 0..<(AgentRun.maxSteps + 25) { r.addStep(AgentStep(id: "\(i)", kind: .read, title: "Read", detail: "")) }
        #expect(r.steps.count == AgentRun.maxSteps && r.steps.last?.id == "\(AgentRun.maxSteps + 24)")
    }
}
