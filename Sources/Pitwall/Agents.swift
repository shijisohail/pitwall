import Foundation

// MARK: Model

/// Where on the Agents canvas a bot hangs out, chosen from what it is doing right now.
enum AgentZone: String, CaseIterable {
    case think, read, search, edit, run, rest
    case hub            // where a new agent spawns from; never a resting place
    var label: String {
        switch self {
        case .think: "Think"
        case .read: "Read"
        case .search: "Search & web"
        case .edit: "Edit"
        case .run: "Run"
        case .rest: "Done"
        case .hub: ""
        }
    }
}

enum AgentState: Equatable {
    case starting, working, done, failed, stopped
    var isFinished: Bool { self == .done || self == .failed || self == .stopped }
}

enum StepKind: Equatable {
    case thinking, speaking, read, search, web, edit, run, agent, other

    var zone: AgentZone {
        switch self {
        case .thinking, .speaking, .agent, .other: .think
        case .read: .read
        case .search, .web: .search
        case .edit: .edit
        case .run: .run
        }
    }

    static func of(tool name: String) -> StepKind {
        switch name {
        case "Read", "NotebookRead", "LS": .read
        case "Glob", "Grep", "ToolSearch": .search
        case "WebFetch", "WebSearch": .web
        case "Edit", "MultiEdit", "Write", "NotebookEdit": .edit
        case "Bash", "BashOutput", "KillShell", "Monitor": .run
        case "Agent", "Task": .agent
        case "TodoWrite", "Skill", "ExitPlanMode", "EnterPlanMode", "AskUserQuestion": .other
        default: name.hasPrefix("mcp__") ? .web : .other
        }
    }
}

struct AgentStep: Identifiable, Equatable {
    enum State { case running, done, failed }
    var id: String
    var kind: StepKind
    var title: String
    var detail: String
    var state: State = .running
}

/// One subagent Claude spawned. Keyed by the `Agent` tool_use id that created it.
struct AgentRun: Identifiable, Equatable {
    var id: String
    var taskID = ""
    var parentID: String?               // tool_use id of the agent that spawned this one; nil = Claude itself
    var name: String
    var type = "general-purpose"
    var prompt = ""
    var background = false
    var depth = 1
    var state: AgentState = .starting
    var startedAt = Date()
    var endedAt: Date?
    var steps: [AgentStep] = []
    var toolUses = 0
    var tokens = 0
    var durationMS = 0
    var activity = ""                   // short text for the speech bubble
    var report: String?
    var zone: AgentZone = .think
    var prevZone: AgentZone = .hub
    var zoneSince = Date()
    var finishOrder = 0                 // order of finishing, to line up resting bots

    static let maxSteps = 60

    /// The zone this agent belongs in right now.
    var wantedZone: AgentZone {
        if state.isFinished { return .rest }
        return steps.last(where: { $0.state == .running })?.kind.zone ?? .think
    }

    mutating func move(to z: AgentZone, at now: Date = Date()) {
        guard z != zone else { return }
        prevZone = zone; zone = z; zoneSince = now
    }

    mutating func addStep(_ s: AgentStep) {
        // Whatever it was doing before is over once it starts something new.
        for i in steps.indices where steps[i].state == .running && steps[i].kind == .thinking { steps[i].state = .done }
        steps.append(s)
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
        activity = s.detail.isEmpty ? s.title : "\(s.title) \(s.detail)"
    }

    mutating func finishStep(_ id: String, failed: Bool) {
        if let i = steps.firstIndex(where: { $0.id == id }) { steps[i].state = failed ? .failed : .done }
    }

    var elapsed: TimeInterval {
        if let e = endedAt { return e.timeIntervalSince(startedAt) }
        return Date().timeIntervalSince(startedAt)
    }
}

// MARK: Tracking

extension Conversation {
    var agentsWorking: Int { agents.filter { !$0.state.isFinished }.count }

    /// Feed every stream event here. Cheap no-op for anything that isn't about agents, and skipped when the
    /// setting is off.
    func trackAgents(_ e: [String: Any]) {
        guard AppSettings.shared.showAgents else { return }
        let parent = e["parent_tool_use_id"] as? String
        switch e["type"] as? String {
        case "system":
            switch e["subtype"] as? String {
            case "task_started": agentStarted(e)
            case "task_progress": agentProgress(e)
            case "task_updated": agentUpdated(e)
            case "task_notification": agentNotified(e)
            default: break
            }
        case "assistant":
            guard let content = (e["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
            agentBlocks(content, parent: parent, event: e)
        case "user":
            guard let content = (e["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
            agentResults(content, parent: parent)
        default: break
        }
    }

    private func agentIndex(_ id: String) -> Int? {
        if let i = agentSlots[id], i < agents.count, agents[i].id == id { return i }
        guard let i = agents.firstIndex(where: { $0.id == id }) else { return nil }
        agentSlots[id] = i
        return i
    }

    @discardableResult
    private func ensureAgent(_ id: String, name: String, parent: String?) -> Int {
        if let i = agentIndex(id) { return i }
        var r = AgentRun(id: id, name: name.isEmpty ? "agent" : name)
        r.parentID = parent
        agents.append(r)
        agentSlots[id] = agents.count - 1
        return agents.count - 1
    }

    private func agentStarted(_ e: [String: Any]) {
        guard let tid = e["tool_use_id"] as? String else { return }
        let i = ensureAgent(tid, name: e["description"] as? String ?? "", parent: nil)
        agents[i].taskID = e["task_id"] as? String ?? agents[i].taskID
        if let d = e["description"] as? String, !d.isEmpty { agents[i].name = d }
        if let t = e["subagent_type"] as? String, !t.isEmpty { agents[i].type = t }
        if let p = e["prompt"] as? String { agents[i].prompt = Limits.clip(p, to: 6_000) }
        agents[i].background = e["is_backgrounded"] as? Bool ?? agents[i].background
        agents[i].depth = e["spawn_depth"] as? Int ?? agents[i].depth
        if !agents[i].state.isFinished { agents[i].state = .working }
        agents[i].move(to: agents[i].wantedZone)
    }

    private func applyUsage(_ u: [String: Any]?, to i: Int) {
        guard let u else { return }
        if let t = u["total_tokens"] as? Int { agents[i].tokens = t }
        if let n = u["tool_uses"] as? Int { agents[i].toolUses = n }
        if let d = u["duration_ms"] as? Int { agents[i].durationMS = d }
    }

    private func agentProgress(_ e: [String: Any]) {
        guard let tid = e["tool_use_id"] as? String, let i = agentIndex(tid) else { return }
        applyUsage(e["usage"] as? [String: Any], to: i)
        // The CLI's own one-line description ("Running Count entries…") is the best speech-bubble text.
        if let d = e["description"] as? String, !d.isEmpty, !agents[i].state.isFinished { agents[i].activity = d }
    }

    private static func state(from status: String) -> AgentState {
        switch status.lowercased() {
        case "completed", "done", "success": .done
        case "failed", "error": .failed
        case "killed", "stopped", "cancelled", "canceled": .stopped
        default: .working
        }
    }

    private func finish(_ i: Int, _ s: AgentState, at date: Date = Date()) {
        guard !agents[i].state.isFinished else { return }
        agents[i].state = s
        agents[i].endedAt = date
        for k in agents[i].steps.indices where agents[i].steps[k].state == .running { agents[i].steps[k].state = s == .done ? .done : .failed }
        agentFinishCount += 1
        agents[i].finishOrder = agentFinishCount
        agents[i].move(to: .rest)
    }

    private func agentUpdated(_ e: [String: Any]) {
        guard let task = e["task_id"] as? String, let i = agents.firstIndex(where: { $0.taskID == task }),
              let patch = e["patch"] as? [String: Any], let status = patch["status"] as? String else { return }
        let s = Self.state(from: status)
        if s.isFinished { finish(i, s, at: (patch["end_time"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()) }
    }

    private func agentNotified(_ e: [String: Any]) {
        guard let tid = e["tool_use_id"] as? String else { return }
        let i = ensureAgent(tid, name: "", parent: nil)
        applyUsage(e["usage"] as? [String: Any], to: i)
        if let s = e["summary"] as? String, !s.isEmpty { agents[i].report = Limits.clip(s, to: 8_000) }
        finish(i, Self.state(from: e["status"] as? String ?? "completed"))
    }

    /// An agent's own thinking / text / tool calls (events tagged with `parent_tool_use_id`), and any `Agent` call,
    /// whether made by Claude or by another agent.
    private func agentBlocks(_ content: [[String: Any]], parent: String?, event e: [String: Any]) {
        for c in content {
            switch c["type"] as? String {
            case "tool_use":
                let name = c["name"] as? String ?? ""
                let id = c["id"] as? String ?? UUID().uuidString
                let input = c["input"] as? [String: Any] ?? [:]
                if name == "Agent" || name == "Task" {
                    let i = ensureAgent(id, name: input["description"] as? String ?? "", parent: parent)
                    agents[i].parentID = parent
                    if let t = input["subagent_type"] as? String { agents[i].type = t }
                    if let p = input["prompt"] as? String, agents[i].prompt.isEmpty { agents[i].prompt = Limits.clip(p, to: 6_000) }
                    agents[i].background = input["run_in_background"] as? Bool ?? agents[i].background
                }
                if let parent, let pi = agentIndex(parent) { addStep(StepKind.of(tool: name), id: id, name: name, input: input, to: pi) }
            case "thinking":
                if let parent {
                    let pi = agentIndex(parent) ?? ensureAgent(parent, name: e["task_description"] as? String ?? "", parent: nil)
                    agents[pi].addStep(AgentStep(id: UUID().uuidString, kind: .thinking, title: "Thinking", detail: ""))
                    agents[pi].move(to: agents[pi].wantedZone)
                }
            case "text":
                if let parent, let pi = agentIndex(parent), let t = c["text"] as? String, !t.isEmpty {
                    agents[pi].report = Limits.clip(t, to: 8_000)      // the last thing it said is its report if no summary arrives
                    agents[pi].addStep(AgentStep(id: UUID().uuidString, kind: .speaking, title: "Writing", detail: String(t.prefix(60)), state: .done))
                    agents[pi].move(to: agents[pi].wantedZone)
                }
            default: break
            }
        }
    }

    private func addStep(_ kind: StepKind, id: String, name: String, input: [String: Any], to i: Int) {
        var b = Block(kind: .tool); b.toolName = name
        if let d = try? JSONSerialization.data(withJSONObject: input) { b.inputJSON = String(decoding: d, as: UTF8.self) }
        agents[i].addStep(AgentStep(id: id, kind: kind, title: name, detail: String(b.toolSummary.prefix(80))))
        agents[i].move(to: agents[i].wantedZone)
    }

    private func agentResults(_ content: [[String: Any]], parent: String?) {
        for c in content where c["type"] as? String == "tool_result" {
            guard let tid = c["tool_use_id"] as? String else { continue }
            let failed = c["is_error"] as? Bool ?? false
            if let parent, let pi = agentIndex(parent) {
                agents[pi].finishStep(tid, failed: failed)
                agents[pi].move(to: agents[pi].wantedZone)
            }
            // A foreground `Agent` call returns the agent's report as its tool result. The async launch notice is not one.
            if let i = agentIndex(tid), !agents[i].state.isFinished {
                let text = Self.resultText(c["content"])
                if !text.hasPrefix("Async agent launched") {
                    if !text.isEmpty { agents[i].report = Limits.clip(text, to: 8_000) }
                    finish(i, failed ? .failed : .done)
                }
            }
        }
    }

    private static func resultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        return (content as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
    }

    /// Start over for the current setting: cleared when the Agent view is off, rebuilt from the transcript when it is on.
    func resetAgents() {
        agents = []; agentSlots = [:]; agentFinishCount = 0
        seedAgentsFromHistory()        // a no-op while the setting is off
    }

    /// A reopened session has no live events, so rebuild what we can from its transcript: every `Agent` call, whether it
    /// finished, and its counts from the `<task-notification>` messages. Runs that already exist are left alone.
    func seedAgentsFromHistory() {
        guard AppSettings.shared.showAgents else { return }
        var notes: [String: TaskNotification] = [:]
        for m in messages where m.role == .user {
            for b in m.blocks where b.kind == .text {
                for n in TaskNotification.split(b.text).notes where !n.toolUseID.isEmpty { notes[n.toolUseID] = n }
            }
        }
        for m in messages {
            for b in m.blocks where b.kind == .tool && (b.toolName == "Agent" || b.toolName == "Task") {
                let input = b.input
                let key = b.toolID.isEmpty ? b.id : b.toolID
                if agentIndex(key) != nil { continue }
                var r = AgentRun(id: key, name: input["description"] as? String ?? "agent")
                r.type = input["subagent_type"] as? String ?? "general-purpose"
                r.prompt = Limits.clip(input["prompt"] as? String ?? "", to: 6_000)
                r.background = input["run_in_background"] as? Bool ?? false
                r.startedAt = m.date; r.zone = .rest; r.prevZone = .rest
                let launched = (b.result ?? "").hasPrefix("Async agent launched")
                if let n = notes[key] {
                    r.state = Self.state(from: n.status); if r.state == .working { r.state = .done }
                    r.durationMS = n.durationMS ?? 0; r.toolUses = n.toolUses ?? 0; r.tokens = n.tokens ?? 0
                    r.endedAt = r.startedAt.addingTimeInterval(Double(r.durationMS) / 1000)
                } else if b.result != nil, !launched {
                    r.state = b.isError ? .failed : .done
                    r.report = Limits.clip(b.result ?? "", to: 8_000)
                } else {
                    r.state = .stopped             // launched, but no outcome was ever recorded
                }
                agentFinishCount += 1; r.finishOrder = agentFinishCount
                agents.append(r); agentSlots[key] = agents.count - 1
            }
        }
    }
}
