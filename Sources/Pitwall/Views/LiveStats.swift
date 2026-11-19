import SwiftUI

/// Per-session numbers for the Live Stats panel, derived from what the board already holds in memory.
struct SessionStats: Identifiable {
    let id: String
    let title: String
    let project: String
    let isRunning: Bool
    let contextTokens: Int
    let contextWindow: Int
    let toolCalls: Int
    let toolsRunning: Int
    let toolsFailed: Int
    let approvals: Int
    let agents: Int
    let turnStart: Date?
    let updatedAt: Date

    var contextFraction: Double { contextWindow > 0 ? min(1, Double(contextTokens) / Double(contextWindow)) : 0 }

    @MainActor init(_ c: Conversation) {
        id = c.id
        title = c.title
        project = (c.cwd as NSString).lastPathComponent
        isRunning = c.isRunning
        contextTokens = c.contextTokens
        contextWindow = c.contextWindow
        var calls = 0, running = 0, failed = 0
        for m in c.messages {
            for b in m.blocks where b.kind == .tool {
                calls += 1
                if b.result == nil { if c.isRunning { running += 1 } } else if b.isError { failed += 1 }
            }
        }
        toolCalls = calls; toolsRunning = running; toolsFailed = failed
        approvals = c.approvals.count
        agents = c.agentsWorking
        turnStart = c.turnStart
        updatedAt = c.updatedAt
    }
}

/// A ticking duration. Only this small view re-renders each second, not the whole panel.
private struct Elapsed: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(ctx.date.timeIntervalSince(since)))
        }
    }

    static func format(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        if t < 60 { return "\(t)s" }
        if t < 3600 { return "\(t / 60)m \(t % 60)s" }
        return "\(t / 3600)h \((t % 3600) / 60)m"
    }
}

struct LiveStatsSheet: View {
    @Environment(Store.self) private var store

    private var sessions: [SessionStats] {
        let start = Calendar.current.startOfDay(for: Date())
        return store.conversations
            .filter { $0.isRunning || $0.externallyActive || !$0.approvals.isEmpty || $0.updatedAt >= start }
            .filter { store.owner($0) != nil }
            .sorted { ($0.isRunning ? 1 : 0, $0.updatedAt) > ($1.isRunning ? 1 : 0, $1.updatedAt) }
            .map(SessionStats.init)
    }

    var body: some View {
        let rows = sessions
        SheetFrame(title: "Live stats", width: 760, height: 560) {
            VStack(alignment: .leading, spacing: 14) {
                totals(rows)
                if rows.isEmpty {
                    Text("No sessions active today.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView { VStack(spacing: 8) { ForEach(rows) { row($0) } }.padding(.bottom, 4) }
                }
            }
            .padding(16)
        }
    }

    private func totals(_ r: [SessionStats]) -> some View {
        let ctx = r.reduce(0) { $0 + $1.contextTokens }
        return HStack(spacing: 0) {
            tile("\(r.filter(\.isRunning).count)", "working", HTB.green)
            tile("\(ctx / 1000)k", "context tokens", HTB.cyan)
            tile("\(r.reduce(0) { $0 + $1.toolCalls })", "tool calls", HTB.amber)
            tile("\(r.reduce(0) { $0 + $1.toolsFailed })", "failed", .red)
            tile("\(r.reduce(0) { $0 + $1.approvals })", "awaiting you", HTB.amber)
            if let u = store.usage {
                tile("\(Int(u.fiveHour * 100))%", "5h limit", HTB.green)
                tile("\(Int(u.sevenDay * 100))%", "7d limit", HTB.cyan)
            }
        }
        .padding(.vertical, 10)
        .panel(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(color).contentTransition(.numericText())
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func row(_ s: SessionStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(s.isRunning ? HTB.green : Color.gray).frame(width: 7, height: 7)
                Text(s.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(s.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                timing(s)
            }
            HStack(spacing: 10) {
                ProgressView(value: s.contextFraction).tint(s.contextFraction > 0.85 ? .red : s.contextFraction > 0.6 ? HTB.amber : HTB.cyan)
                Text("\(s.contextTokens / 1000)k / \(s.contextWindow / 1000)k").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            HStack(spacing: 14) {
                chip("\(s.toolCalls) tool calls", .secondary)
                if s.toolsRunning > 0 { chip("\(s.toolsRunning) running", HTB.green) }
                if s.toolsFailed > 0 { chip("\(s.toolsFailed) failed", .red) }
                if s.approvals > 0 { chip("\(s.approvals) awaiting you", HTB.amber) }
                if s.agents > 0 { chip("\(s.agents) agents", Color(red: 1, green: 0.45, blue: 0.7)) }
                Spacer()
            }
        }
        .padding(12)
        .panel(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private func timing(_ s: SessionStats) -> some View {
        HStack(spacing: 4) {
            if let t = s.turnStart {
                Text("working").foregroundStyle(.secondary); Elapsed(since: t).foregroundStyle(HTB.green)
            } else {
                Text("idle").foregroundStyle(.secondary); Elapsed(since: s.updatedAt)
            }
        }.font(.system(size: 11.5, design: .monospaced))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color)
    }
}
