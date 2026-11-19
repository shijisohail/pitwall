import Foundation

/// The limits Claude Code puts on parallel work, so Pitwall can warn before Claude runs into one.
///
/// Defaults are the documented ones (code.claude.com/docs: sub-agents, workflows). Each can be changed with an
/// environment variable, which people usually set in the `env` block of `~/.claude/settings.json`, so that file is read
/// too. They are advisory numbers for the UI; the CLI enforces the real limits.
enum ParallelLimits {
    static let subagentsKey = "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"
    static let depthKey = "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"
    static let workflowAgentsKey = "CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS"

    /// Subagents running at once in one session. At the limit the `Agent` tool fails and Claude is told not to retry.
    static let defaultSubagents = 20
    /// Layers of subagents below the main conversation.
    static let defaultDepth = 3
    /// Agents a dynamic workflow runs at once (fewer on a machine with few CPUs).
    static let defaultWorkflowAgents = 16

    /// What the CLI answers when `Agent` is called at the limit.
    static let subagentLimitMessage = "Concurrent subagent limit reached"

    enum Pressure: Equatable { case ok, near, full }

    /// `near` from 80% of the limit, `full` at it.
    static func pressure(running: Int, limit: Int) -> Pressure {
        guard limit > 0 else { return .ok }
        if running >= limit { return .full }
        return Double(running) >= Double(limit) * 0.8 ? .near : .ok
    }

    /// A positive whole number from text, else nil (zero, negatives and junk mean "not set").
    static func positiveInt(_ s: String?) -> Int? {
        guard let s, let n = Int(s.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return n
    }

    /// Settings-file `env` wins over the process environment, which wins over the documented default.
    static func limit(_ key: String, default d: Int, settingsEnv: [String: String], processEnv: [String: String]) -> Int {
        positiveInt(settingsEnv[key]) ?? positiveInt(processEnv[key]) ?? d
    }

    /// The `env` block of a Claude Code settings file, as strings. Missing or malformed files give an empty map.
    static func settingsEnv(fromJSON data: Data?) -> [String: String] {
        guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = o["env"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in env {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { out[k] = n.stringValue }   // a JSON `true` is not 1
        }
        return out
    }

    // MARK: Current values for the UI

    @MainActor private static var cached: (at: Date, env: [String: String])?

    @MainActor private static func userEnv() -> [String: String] {
        if let c = cached, Date().timeIntervalSince(c.at) < 20 { return c.env }
        let env = settingsEnv(fromJSON: FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/settings.json"))
        cached = (Date(), env)
        return env
    }

    @MainActor static var subagents: Int {
        limit(subagentsKey, default: defaultSubagents, settingsEnv: userEnv(), processEnv: ProcessInfo.processInfo.environment)
    }
    @MainActor static var depth: Int {
        limit(depthKey, default: defaultDepth, settingsEnv: userEnv(), processEnv: ProcessInfo.processInfo.environment)
    }
}
