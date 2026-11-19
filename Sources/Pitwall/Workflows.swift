import Foundation

// MARK: Model

struct WorkflowPhase: Identifiable, Equatable {
    var index: Int
    var title: String
    var id: Int { index }
}

/// One agent inside a dynamic workflow, from the CLI's `workflow_progress` snapshot.
struct WorkflowAgent: Identifiable, Equatable {
    enum State: Equatable { case running, done, failed, stopped }

    var id: String
    var index: Int
    var label: String
    var phaseIndex: Int
    var phaseTitle: String
    var model = ""
    var state: State = .running
    var tool = ""                  // the tool it used last, e.g. "Read"
    var toolSummary = ""           // and on what, e.g. a path
    var prompt = ""
    var result = ""
    var error = ""
    var tokens = 0
    var toolCalls = 0
    var durationMS = 0
    var attempt = 1

    init(id: String, index: Int, label: String, phaseIndex: Int, phaseTitle: String) {
        self.id = id; self.index = index; self.label = label; self.phaseIndex = phaseIndex; self.phaseTitle = phaseTitle
    }

    /// `{"type":"workflow_agent", "index", "label", "phaseIndex", "phaseTitle", "agentId", "model", "state": start|progress|done|error, ...}`
    init?(json j: [String: Any]) {
        guard j["type"] as? String == "workflow_agent", let index = j["index"] as? Int else { return nil }
        let label = j["label"] as? String ?? "agent \(index)"
        self.init(id: j["agentId"] as? String ?? "agent-\(index)", index: index, label: label,
                  phaseIndex: j["phaseIndex"] as? Int ?? 0, phaseTitle: j["phaseTitle"] as? String ?? "")
        model = j["model"] as? String ?? ""
        switch j["state"] as? String {
        case "done": state = .done
        case "error": state = .failed
        default: state = .running
        }
        tool = j["lastToolName"] as? String ?? ""
        toolSummary = j["lastToolSummary"] as? String ?? ""
        prompt = Limits.clip(j["promptPreview"] as? String ?? "", to: 2_000)
        result = Limits.clip(j["resultPreview"] as? String ?? "", to: 2_000)
        error = j["error"] as? String ?? ""
        tokens = j["tokens"] as? Int ?? 0
        toolCalls = j["toolCalls"] as? Int ?? 0
        durationMS = j["durationMs"] as? Int ?? 0
        attempt = j["attempt"] as? Int ?? 1
    }

    var isFinished: Bool { state != .running }
}

/// A dynamic workflow Claude started with the `Workflow` tool: a script that runs many agents in phases. Mirrors the CLI's
/// `task_*` events with `task_type: "local_workflow"` (docs/CLAUDE_CODE_PROTOCOL.md).
struct WorkflowRun: Identifiable, Equatable {
    enum Status: Equatable { case running, completed, stopped, failed }

    let id: String                 // the CLI's task_id
    var toolUseID = ""
    var name: String
    var summary = ""               // the script's own one-line description
    var script = ""
    var status: Status = .running
    var startedAt = Date()
    var endedAt: Date?
    var phases: [WorkflowPhase] = []
    var agents: [WorkflowAgent] = []
    var tokens = 0
    var toolUses = 0
    var activity = ""              // "Read: reader 2", the CLI's own one-liner for what just happened
    var outputFile: String?

    var isRunning: Bool { status == .running }
    var finishedAgents: Int { agents.filter(\.isFinished).count }
    var failedAgents: Int { agents.filter { $0.state == .failed }.count }
    var runningAgents: Int { agents.filter { !$0.isFinished }.count }

    func agents(in phase: WorkflowPhase) -> [WorkflowAgent] { agents.filter { $0.phaseIndex == phase.index } }

    /// The phase work is happening in: the first one with a running agent, else the last one that has agents.
    var currentPhase: WorkflowPhase? {
        if let p = phases.first(where: { !agents(in: $0).filter { !$0.isFinished }.isEmpty }) { return p }
        return phases.last(where: { !agents(in: $0).isEmpty }) ?? phases.first
    }

    var progressLine: String {
        var p: [String] = []
        if !agents.isEmpty { p.append("\(finishedAgents) of \(agents.count) agents \(failedAgents > 0 ? "finished" : "done")") }
        if let c = currentPhase, phases.count > 1 { p.append("phase \(c.index) of \(phases.count): \(c.title)") }
        return p.joined(separator: " · ")
    }

    static func status(forCLI s: String?) -> Status? {
        switch s {
        case "completed": .completed
        case "killed", "stopped", "cancelled", "canceled": .stopped
        case "failed", "error": .failed
        case "running", "pending": .running
        default: nil
        }
    }
}

// MARK: Tracking

extension Conversation {
    /// How many finished workflows to keep on screen, newest first.
    static let finishedWorkflowsKept = 3

    private func workflowIndex(_ id: String) -> Int? { workflows.firstIndex { $0.id == id } }

    /// Called for every event. A cheap no-op unless it is about a `local_workflow` task.
    func trackWorkflows(_ e: [String: Any]) {
        guard e["type"] as? String == "system", let sub = e["subtype"] as? String else { return }
        switch sub {
        case "task_started":
            guard e["task_type"] as? String == "local_workflow", let id = e["task_id"] as? String else { return }
            var w = WorkflowRun(id: id, name: e["workflow_name"] as? String ?? e["description"] as? String ?? "Workflow")
            w.toolUseID = e["tool_use_id"] as? String ?? ""
            w.summary = e["description"] as? String ?? ""
            w.script = Limits.clip(e["prompt"] as? String ?? "", to: 20_000)
            if let i = workflowIndex(id) { w.startedAt = workflows[i].startedAt; workflows[i] = w } else { workflows.append(w) }
            pruneWorkflows()
        case "task_progress":
            guard let id = e["task_id"] as? String, let i = workflowIndex(id) else { return }
            if let u = e["usage"] as? [String: Any] {
                if let t = u["total_tokens"] as? Int { workflows[i].tokens = t }
                if let n = u["tool_uses"] as? Int { workflows[i].toolUses = n }
            }
            if workflows[i].isRunning, let d = e["description"] as? String, !d.isEmpty { workflows[i].activity = d }
            // The agent list arrives as a full snapshot, and only when it changed.
            if let items = e["workflow_progress"] as? [[String: Any]] { applyWorkflowProgress(items, to: i) }
        case "task_updated":
            guard let id = e["task_id"] as? String, let i = workflowIndex(id), let patch = e["patch"] as? [String: Any],
                  let s = WorkflowRun.status(forCLI: patch["status"] as? String), s != .running else { return }
            settleWorkflow(i, s, at: Self.date(fromMillis: patch["end_time"]) ?? Date())
        case "task_notification":
            guard let id = e["task_id"] as? String, let i = workflowIndex(id) else { return }
            if let f = e["output_file"] as? String, !f.isEmpty { workflows[i].outputFile = f }
            if let u = e["usage"] as? [String: Any], let t = u["total_tokens"] as? Int { workflows[i].tokens = t }
            if let s = WorkflowRun.status(forCLI: e["status"] as? String), s != .running { settleWorkflow(i, s, at: Date()) }
        case "background_tasks_changed":
            // The CLI's list of live background tasks: a workflow we think is running that has left it has ended.
            let live = Set((e["tasks"] as? [[String: Any]] ?? []).compactMap { $0["task_id"] as? String })
            for i in workflows.indices where workflows[i].isRunning && !live.contains(workflows[i].id) {
                settleWorkflow(i, .completed, at: Date())
            }
        default: return
        }
    }

    private func applyWorkflowProgress(_ items: [[String: Any]], to i: Int) {
        var phases: [WorkflowPhase] = [], agents: [WorkflowAgent] = []
        for it in items {
            switch it["type"] as? String {
            case "workflow_phase":
                if let n = it["index"] as? Int { phases.append(WorkflowPhase(index: n, title: it["title"] as? String ?? "Phase \(n)")) }
            case "workflow_agent":
                if var a = WorkflowAgent(json: it) {
                    if !workflows[i].isRunning, a.state == .running { a.state = workflows[i].status == .completed ? .done : .stopped }
                    agents.append(a)
                }
            default: break
            }
        }
        guard !phases.isEmpty || !agents.isEmpty else { return }
        workflows[i].phases = phases; workflows[i].agents = agents
    }

    private func settleWorkflow(_ i: Int, _ status: WorkflowRun.Status, at date: Date) {
        guard workflows[i].isRunning else { return }
        workflows[i].status = status
        workflows[i].endedAt = date
        // Agents the last snapshot still showed as running did not outlive the workflow.
        for k in workflows[i].agents.indices where workflows[i].agents[k].state == .running {
            workflows[i].agents[k].state = status == .completed ? .done : .stopped
        }
        pruneWorkflows()
    }

    private func pruneWorkflows() {
        let finished = workflows.enumerated().filter { !$0.element.isRunning }
        guard finished.count > Self.finishedWorkflowsKept else { return }
        let oldest = finished.sorted { ($0.element.endedAt ?? .distantPast, $0.offset) < ($1.element.endedAt ?? .distantPast, $1.offset) }
        let drop = Set(oldest.prefix(finished.count - Self.finishedWorkflowsKept).map { $0.element.id })
        workflows.removeAll { drop.contains($0.id) }
    }

    /// The process is gone, and so is everything it was running.
    func endAllWorkflows() {
        for i in workflows.indices where workflows[i].isRunning { settleWorkflow(i, .stopped, at: Date()) }
    }

    var runningWorkflows: [WorkflowRun] { workflows.filter(\.isRunning) }

    // MARK: Controls

    /// Stops the workflow and every agent it is running. The session stays usable.
    func stopWorkflow(_ id: String) { runner?.request("stop_task", ["task_id": id]) }

    func dismissWorkflow(_ id: String) { workflows.removeAll { $0.id == id && !$0.isRunning } }
}
