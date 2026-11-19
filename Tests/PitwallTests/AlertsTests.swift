import Testing
import Foundation
@testable import Pitwall

/// The "needs you" / "finished" notifications: what they say, and when they stay quiet.
@MainActor @Suite struct AlertsTests {
    private func approval(_ kind: Approval.Kind, tool: String = "Bash", input: [String: Any] = [:]) -> Approval {
        Approval(id: "a1", kind: kind, tool: tool, input: input, detail: nil, reason: nil, suggestions: [])
    }

    @Test func describesEachKindOfRequest() {
        #expect(Alerts.describe(approval(.tool, input: ["command": "git push\nrm -rf x"])) == "Bash: git push")
        #expect(Alerts.describe(approval(.plan, tool: "ExitPlanMode")) == "A plan is ready for review")
        #expect(Alerts.describe(approval(.question, tool: "AskUserQuestion", input: ["questions": [["question": "Which DB?"]]])) == "Which DB?")
        #expect(Alerts.describe(approval(.tool, tool: "Edit")) == "Wants to use Edit")
    }

    @Test func notifiesOnlyWhenTheSessionIsNotOnScreen() {
        let (d, w, on) = (Alerts.deliver, Alerts.isWatching, AppSettings.shared.notifyWhenAway)
        defer { Alerts.deliver = d; Alerts.isWatching = w; AppSettings.shared.notifyWhenAway = on }
        let c = Conversation(cwd: "/tmp/proj")
        nonisolated(unsafe) var sent: [Alerts.Message] = []
        Alerts.deliver = { if $0.sessionID == c.id { sent.append($0) } }
        AppSettings.shared.notifyWhenAway = true

        Alerts.isWatching = { _ in true }
        Alerts.needsYou(c, approval(.tool)); Alerts.finished(c)
        #expect(sent.isEmpty)

        Alerts.isWatching = { _ in false }
        Alerts.needsYou(c, approval(.tool, input: ["command": "ls"])); Alerts.finished(c)
        #expect(sent.map(\.needsYou) == [true, false])
        #expect(sent[1].body == "proj")

        AppSettings.shared.notifyWhenAway = false
        Alerts.finished(c)
        #expect(sent.count == 2)
    }
}
