import Foundation
import AppKit
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
    /// The Agent view: track subagents and show them in the inspector's Agents tab. Opt-in (off by default); off also
    /// stops the tracking. Changing it tells every session to rebuild or clear its agents (see `Store`).
    var showAgents: Bool {
        didSet {
            defaults.set(showAgents, forKey: "showAgents")
            if showAgents != oldValue { NotificationCenter.default.post(name: .agentViewChanged, object: nil) }
        }
    }

    /// 0 = solid dark, 1 = as clear as the glass gets. Drives the window's see-through tint and how opaque cards are.
    var glassiness: Double { didSet { defaults.set(glassiness, forKey: "glassiness") } }
    /// How much of the near-black theme colour covers the desktop blur behind the window (0.80 at the default).
    var windowTint: Double { 0.95 - 0.6 * glassiness }
    /// Opacity of the dark fill under cards and buttons, so more glassiness lets more of the glass show (0.55 at the default).
    var cardFill: Double { 0.55 + (0.25 - glassiness) * 0.6 }

    /// Full screen that uses the row beside the camera notch, with tabs on either side of it. Off by default because it
    /// replaces macOS's own full screen (and its Spaces and Split View behaviour) with a custom one.
    var notchFullScreen: Bool {
        didSet { defaults.set(notchFullScreen, forKey: "notchFullScreen"); NotchFullScreen.shared.apply() }
    }

    /// A short sound when a session finishes its turn, so you can look away while it works. On by default.
    var soundOnFinish: Bool { didSet { defaults.set(soundOnFinish, forKey: "soundOnFinish") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = PermissionMode(rawValue: defaults.string(forKey: "defaultPermission") ?? "") ?? .acceptEdits
        defaultPermission = stored == .bypassPermissions ? .acceptEdits : stored
        claudePath = defaults.string(forKey: "claudePath") ?? ""
        animatedBackground = defaults.object(forKey: "animatedBackground") as? Bool ?? false     // costs ~4% CPU while idle, so opt-in
        confirmQuitWhileRunning = defaults.object(forKey: "confirmQuit") as? Bool ?? true
        permissionsTipDismissed = defaults.object(forKey: "permissionsTipDismissed") as? Bool ?? false
        soundOnFinish = defaults.object(forKey: "soundOnFinish") as? Bool ?? true
        glassiness = min(1, max(0, defaults.object(forKey: "glassiness") as? Double ?? 0.25))
        notchFullScreen = defaults.object(forKey: "notchFullScreen") as? Bool ?? false
        showAgents = defaults.object(forKey: "showAgents") as? Bool ?? false
        if !claudePath.isEmpty { ClaudeRunner.pathOverride = claudePath }
    }
}

extension Notification.Name {
    /// Posted when the Agent view is switched on or off.
    static let agentViewChanged = Notification.Name("pitwall.agentViewChanged")
}

/// The "session finished" sound. A system sound, so nothing is bundled; `play` is swappable for tests.
enum FinishSound {
    nonisolated(unsafe) static var play: () -> Void = { NSSound(named: "Glass")?.play() }

    @MainActor static func playIfEnabled() { if AppSettings.shared.soundOnFinish { play() } }
}
