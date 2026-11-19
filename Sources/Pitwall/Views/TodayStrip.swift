import SwiftUI

/// A one-line "today so far" readout under the Pit Wall header: sessions touched, spend, lines changed, agents live.
struct TodayStrip: View {
    let sessions: [Conversation]

    private struct Totals { var sessions = 0, files = 0, added = 0, removed = 0, agents = 0; var cost = 0.0 }

    private var totals: Totals {
        let start = Calendar.current.startOfDay(for: Date())
        var t = Totals()
        for c in sessions where c.updatedAt >= start || c.isRunning {
            t.sessions += 1; t.cost += c.cost; t.agents += c.agentsWorking
            let s = c.diffStat
            t.files += s.files; t.added += s.added; t.removed += s.removed
        }
        return t
    }

    var body: some View {
        let t = totals
        HStack(spacing: 0) {
            stat("\(t.sessions)", t.sessions == 1 ? "session today" : "sessions today", HTB.green)
            divider
            stat(String(format: "$%.2f", t.cost), "spent", HTB.amber)
            divider
            stat("\(t.files)", t.files == 1 ? "file changed" : "files changed", HTB.cyan, trailing: t.files == 0 ? nil : AnyView(delta(t.added, t.removed)))
            if t.agents > 0 { divider; stat("\(t.agents)", t.agents == 1 ? "agent working" : "agents working", Color(red: 1, green: 0.45, blue: 0.7)) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9).padding(.horizontal, 6)
        .panel(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(t.sessions) sessions, \(String(format: "$%.2f", t.cost)) spent, \(t.files) files changed")
    }

    private var divider: some View { Rectangle().fill(HTB.border).frame(width: 1, height: 22).padding(.horizontal, 14) }

    private func delta(_ a: Int, _ r: Int) -> some View {
        HStack(spacing: 4) { Text("+\(a)").foregroundStyle(.green); Text("−\(r)").foregroundStyle(.red) }
            .font(.system(size: 11.5, design: .monospaced))
    }

    private func stat(_ value: String, _ label: String, _ color: Color, trailing: AnyView? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value).font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(color).contentTransition(.numericText())
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            trailing
        }
        .padding(.leading, 8)
    }
}
