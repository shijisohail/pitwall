import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite(.serialized) struct WorkflowTests {
    private func make() -> Conversation {
        let c = Conversation(cwd: "/tmp"); c.store = makeStore(); return c
    }

    @Test func aStartedWorkflowIsTrackedWithItsNameAndScript() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 1) { c.handle(e) }
        #expect(c.workflows.count == 1)
        let w = c.workflows[0]
        #expect(w.id == "we5obch08" && w.name == "txt-read-summarize" && w.toolUseID == "toolu_wf")
        #expect(w.isRunning && w.script.contains("txt-read-summarize"))
        #expect(c.runningWorkflows.count == 1)
    }

    @Test func progressSnapshotsFillPhasesAndAgentsAndOthersKeepThem() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 4) { c.handle(e) }       // the 4th is a snapshot with one agent done
        let w = c.workflows[0]
        #expect(w.phases.map(\.title) == ["Read", "Summarize"])
        #expect(w.agents.map(\.label) == ["reader 1", "reader 2", "reader 3"])
        #expect(w.agents.map(\.state) == [.done, .running, .running])
        #expect(w.finishedAgents == 1 && w.runningAgents == 2)
        #expect(w.tokens == 86067 && w.toolUses == 12)
        #expect(w.agents[0].tokens == 29064 && w.agents[0].durationMS == 4376 && w.agents[0].result == "f1.txt: one-line note")
        #expect(w.agents[2].tool == "Bash")
        #expect(w.currentPhase?.title == "Read")
        #expect(w.progressLine == "1 of 3 agents done · phase 1 of 2: Read")
    }

    @Test func aProgressEventWithoutASnapshotOnlyUpdatesTotalsAndActivity() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 3) { c.handle(e) }       // 3rd carries no workflow_progress
        let w = c.workflows[0]
        #expect(w.agents.count == 3)                                   // the earlier snapshot is kept
        #expect(w.tokens == 5000 && w.activity == "Read: reader 3")
    }

    @Test func stoppingEndsTheWorkflowAndKeepsTheFailedAgent() {
        let c = make()
        for e in workflowFixtureEvents() { c.handle(e) }
        let w = c.workflows[0]
        #expect(w.status == .stopped && !w.isRunning)
        #expect(w.endedAt == Date(timeIntervalSince1970: 1_794_568_040.626))
        #expect(w.outputFile == "/tmp/we5obch08.output")
        #expect(w.agents.map(\.state) == [.done, .done, .done, .failed])
        #expect(w.agents[3].error == "Stopped because the workflow was stopped")
        #expect(w.progressLine.hasPrefix("4 of 4 agents finished"))
        #expect(c.runningWorkflows.isEmpty)
    }

    @Test func aWorkflowDoesNotBecomeAnAgentOrACommand() {
        AppSettings.shared.showAgents = true
        defer { AppSettings.shared.showAgents = false }
        let c = make()
        for e in workflowFixtureEvents() { c.handle(e) }
        #expect(c.agents.isEmpty)
        #expect(c.tasks.isEmpty)
    }

    @Test func aBackgroundCommandDoesNotBecomeAPhantomAgent() {
        AppSettings.shared.showAgents = true
        defer { AppSettings.shared.showAgents = false }
        let c = make()
        c.handle(["type": "system", "subtype": "task_started", "task_id": "b1", "tool_use_id": "toolu_bash", "description": "npm test", "task_type": "local_bash", "is_backgrounded": true])
        c.handle(["type": "system", "subtype": "task_progress", "task_id": "b1", "tool_use_id": "toolu_bash", "description": "tick"])
        c.handle(["type": "system", "subtype": "task_notification", "task_id": "b1", "tool_use_id": "toolu_bash", "status": "completed", "summary": "done"])
        #expect(c.agents.isEmpty)
        #expect(c.tasks.count == 1 && c.tasks[0].status == .completed)
    }

    @Test func aWorkflowThatLeavesTheLiveListHasEnded() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 2) { c.handle(e) }
        c.handle(["type": "system", "subtype": "background_tasks_changed", "tasks": [["task_id": "we5obch08"]]])
        #expect(c.workflows[0].isRunning)
        c.handle(["type": "system", "subtype": "background_tasks_changed", "tasks": []])
        #expect(c.workflows[0].status == .completed)
        #expect(c.workflows[0].agents.allSatisfy { $0.state == .done })      // none still shown as running
    }

    @Test func theProcessEndingStopsWhatWasRunning() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 4) { c.handle(e) }
        c.endAllWorkflows()
        #expect(c.workflows[0].status == .stopped)
        #expect(c.workflows[0].agents.map(\.state) == [.done, .stopped, .stopped])
    }

    @Test func onlyTheNewestFinishedWorkflowsAreKept() {
        let c = make()
        for i in 0..<(Conversation.finishedWorkflowsKept + 2) {
            c.handle(["type": "system", "subtype": "task_started", "task_id": "w\(i)", "tool_use_id": "u\(i)", "task_type": "local_workflow", "workflow_name": "n\(i)"])
            c.handle(["type": "system", "subtype": "task_updated", "task_id": "w\(i)", "patch": ["status": "completed", "end_time": 1_794_568_000_000 + i * 1000]])
        }
        #expect(c.workflows.count == Conversation.finishedWorkflowsKept)
        #expect(c.workflows.first?.id == "w2")
        c.dismissWorkflow("w2")
        #expect(c.workflows.count == Conversation.finishedWorkflowsKept - 1)
    }

    @Test func aRunningWorkflowCannotBeDismissed() {
        let c = make()
        for e in workflowFixtureEvents(upTo: 2) { c.handle(e) }
        c.dismissWorkflow("we5obch08")
        #expect(c.workflows.count == 1)
    }
}
