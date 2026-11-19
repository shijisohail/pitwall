import Testing
import Foundation
@testable import Pitwall

/// Serialized: flips the shared `AppSettings.shared.showAgents`.
@MainActor @Suite(.serialized) struct AgentControlTests {
    private func make() -> Conversation {
        AppSettings.shared.showAgents = true
        let s = makeStore()
        let c = Conversation(cwd: NSTemporaryDirectory()); c.store = s
        s.conversations.append(c)
        return c
    }
    private func spawn(_ c: Conversation, task: String = "t1", toolUse: String = "toolu_a1") {
        c.handle(["type": "system", "subtype": "task_started", "task_id": task, "run_id": "r1", "tool_use_id": toolUse,
                  "description": "worker", "subagent_type": "Explore", "task_type": "local_agent", "spawn_depth": 1])
    }

    @Test func aRunningAgentCanBeStoppedAndAFinishedOneCannot() {
        let c = make(); defer { AppSettings.shared.showAgents = false }
        spawn(c)
        #expect(c.agents.count == 1 && c.agents[0].taskID == "t1" && c.agents[0].canStop)
        c.handle(["type": "system", "subtype": "task_updated", "task_id": "t1", "patch": ["status": "completed", "end_time": 1_793_583_301_079]])
        #expect(!c.agents[0].canStop)
    }

    @Test func stopAgentAsksTheCliToStopItsTaskAndTheRowFollows() async {
        await withFakeClaude {
            let c = make(); defer { AppSettings.shared.showAgents = false }
            c.send("hi"); #expect(await waitUntil { !c.isRunning })
            spawn(c)
            c.stopAgent("toolu_a1")
            #expect(await waitUntil { c.agents.first?.state == .stopped })
            #expect(c.agentsWorking == 0)
            c.teardown()
        }
    }

    @Test func stopAllStopsEveryRunningAgent() async {
        await withFakeClaude {
            let c = make(); defer { AppSettings.shared.showAgents = false }
            c.send("hi"); #expect(await waitUntil { !c.isRunning })
            spawn(c)                                                // the fake only knows task "t1"; a second one stays running
            spawn(c, task: "t2", toolUse: "toolu_a2")
            #expect(c.agents.filter(\.canStop).count == 2)
            c.stopAllAgents()
            #expect(await waitUntil { c.agents.first { $0.taskID == "t1" }?.state == .stopped })
            #expect(c.agents.first { $0.taskID == "t2" }?.state != .stopped)
            c.teardown()
        }
    }

    @Test func stoppingAnUnknownOrFinishedAgentSendsNothingAndDoesNotCrash() {
        let c = make(); defer { AppSettings.shared.showAgents = false }
        c.stopAgent("nope")
        spawn(c)
        c.handle(["type": "system", "subtype": "task_notification", "task_id": "t1", "tool_use_id": "toolu_a1", "status": "completed", "summary": "s"])
        c.stopAgent("toolu_a1")
        #expect(c.agents[0].state == .done)
    }

    @Test func theSubagentLimitErrorIsExplainedOncePerTurn() {
        let c = make(); defer { AppSettings.shared.showAgents = false }
        func limitResult(_ id: String) {
            c.messages.append(ChatMessage(role: .assistant, blocks: [{ var b = Block(kind: .tool); b.toolID = id; b.toolName = "Agent"; return b }()]))
            c.handle(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "is_error": true,
                                                              "content": "Concurrent subagent limit reached (20). Do not retry."]]]])
        }
        limitResult("a"); limitResult("b")
        let notes = c.messages.flatMap(\.blocks).filter { $0.kind == .notice && $0.text.contains("subagents at once") }
        #expect(notes.count == 1)
        #expect(notes[0].text.contains(ParallelLimits.subagentsKey))
    }
}
