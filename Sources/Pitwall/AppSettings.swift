import Foundation
import Observation

/// User preferences (Settings, ⌘,). Stored in UserDefaults; nothing here is ever prompt or transcript content.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults: UserDefaults

    /// Mode new sessions start in. Full access is deliberately not selectable as a default.
    var defaultPermission: PermissionMode { didSet { defaults.set(defaultPermission.rawValue, forKey: "defaultPermission") } }
    /// Empty = auto-detect `claude`.
    var claudePath: String {
        didSet { defaults.set(claudePath, forKey: "claudePath"); ClaudeRunner.pathOverride = claudePath.isEmpty ? nil : claudePath }
    }
    var animatedBackground: Bool { didSet { defaults.set(animatedBackground, forKey: "animatedBackground") } }
    var confirmQuitWhileRunning: Bool { didSet { defaults.set(confirmQuitWhileRunning, forKey: "confirmQuit") } }
    /// Set once the user has seen (and dismissed) the one-time tip about macOS folder permissions.
    var permissionsTipDismissed: Bool { didSet { defaults.set(permissionsTipDismissed, forKey: "permissionsTipDismissed") } }
    /// Track subagents and show them in the inspector's Agents tab. Off also stops the tracking.
    var showAgents: Bool { didSet { defaults.set(showAgents, forKey: "showAgents") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = PermissionMode(rawValue: defaults.string(forKey: "defaultPermission") ?? "") ?? .acceptEdits
        defaultPermission = stored == .bypassPermissions ? .acceptEdits : stored
        claudePath = defaults.string(forKey: "claudePath") ?? ""
        animatedBackground = defaults.object(forKey: "animatedBackground") as? Bool ?? false     // costs ~4% CPU while idle, so opt-in
        confirmQuitWhileRunning = defaults.object(forKey: "confirmQuit") as? Bool ?? true
        permissionsTipDismissed = defaults.object(forKey: "permissionsTipDismissed") as? Bool ?? false
        showAgents = defaults.object(forKey: "showAgents") as? Bool ?? true
        if !claudePath.isEmpty { ClaudeRunner.pathOverride = claudePath }
    }
}
