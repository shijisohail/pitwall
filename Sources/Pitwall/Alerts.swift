import Foundation
import AppKit
import UserNotifications

/// macOS notifications for the two moments you have to look up for: a session needs an answer, or it finished.
/// Sent only while Pitwall is in the background or the session isn't the one on screen, so it never nags about
/// what you are already watching. Clicking one opens that session. `deliver` is swappable for tests.
enum Alerts {
    struct Message: Equatable {
        var title: String
        var body: String
        var sessionID: String
        var needsYou: Bool
    }

    nonisolated(unsafe) static var deliver: (Message) -> Void = { UNAlerts.shared.post($0) }
    /// Whether the user is looking at this session right now. Swappable for tests.
    @MainActor static var isWatching: (Conversation) -> Bool = { c in
        NSApp.isActive && Store.shared.selection == c.id && !Store.shared.showBoard
    }

    @MainActor static func needsYou(_ c: Conversation, _ a: Approval) {
        guard AppSettings.shared.notifyWhenAway, !isWatching(c) else { return }
        deliver(Message(title: "\(c.title) needs you", body: describe(a), sessionID: c.id, needsYou: true))
    }

    @MainActor static func finished(_ c: Conversation) {
        guard AppSettings.shared.notifyWhenAway, !isWatching(c) else { return }
        let project = (c.cwd as NSString).lastPathComponent
        deliver(Message(title: "\(c.title) finished", body: project, sessionID: c.id, needsYou: false))
    }

    static func describe(_ a: Approval) -> String {
        switch a.kind {
        case .plan: return "A plan is ready for review"
        case .question:
            let q = (a.input["questions"] as? [[String: Any]])?.first?["question"] as? String
            return q ?? "Claude has a question"
        case .tool:
            let cmd = a.input["command"] as? String ?? a.input["file_path"] as? String ?? a.detail ?? ""
            let first = cmd.split(separator: "\n").first.map(String.init) ?? ""
            return first.isEmpty ? "Wants to use \(a.tool)" : "\(a.tool): \(Limits.clip(first, to: 90))"
        }
    }
}

/// The real delivery. Only works from a bundled app, so anything else (tests, scratch harnesses) is a no-op.
final class UNAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UNAlerts()
    private var asked = false
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    func post(_ m: Alerts.Message) {
        guard let center else { return }
        center.delegate = self
        if !asked { asked = true; center.requestAuthorization(options: [.alert]) { _, _ in } }
        let c = UNMutableNotificationContent()
        c.title = m.title; c.body = m.body; c.userInfo = ["session": m.sessionID]
        c.threadIdentifier = m.sessionID
        if m.needsYou { c.interruptionLevel = .timeSensitive }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        guard let id = r.notification.request.content.userInfo["session"] as? String else { return }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let c = Store.shared.conversations.first(where: { $0.id == id }) { Store.shared.open(c) }
        }
    }
}
