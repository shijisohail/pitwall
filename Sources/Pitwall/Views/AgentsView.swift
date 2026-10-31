import SwiftUI

private func agentTint(_ run: AgentRun) -> Color {
    switch run.state {
    case .starting: HTB.cyan
    case .working: run.zone == .think ? HTB.cyan : HTB.green
    case .done: Color(red: 0.73, green: 0.50, blue: 1.0)
    case .failed: HTB.red
    case .stopped: Color.secondary
    }
}

private func stateWord(_ run: AgentRun) -> String {
    switch run.state {
    case .starting: "Starting"
    case .working: run.zone == .think ? "Thinking" : "Working"
    case .done: "Done"
    case .failed: "Failed"
    case .stopped: "Stopped"
    }
}

private func compact(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }

private func clock(_ s: TimeInterval) -> String {
    let t = max(Int(s), 0); return t < 60 ? "\(t)s" : "\(t / 60)m \(t % 60)s"
}

/// The inspector's Agents tab: a canvas of roaming bots, and a roster that says the same thing in words.
struct AgentsTab: View {
    @Bindable var conversation: Conversation
    @State private var selected: String?

    init(conversation: Conversation, selected: String? = nil) {
        self.conversation = conversation
        _selected = State(initialValue: selected)
    }

    private var agents: [AgentRun] { conversation.agents }

    private var summary: String {
        let working = agents.filter { !$0.state.isFinished }.count
        let done = agents.filter { $0.state == .done }.count
        let failed = agents.filter { $0.state == .failed }.count
        var parts = ["\(agents.count) spawned", "\(working) working", "\(done) done"]
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(agents.isEmpty ? "No agents yet" : summary)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                .accessibilityLabel(agents.isEmpty ? "No agents yet" : summary)
            AgentCanvas(conversation: conversation, selected: $selected)
            if agents.isEmpty {
                Text("When Claude spawns subagents they appear here as little bots, moving to Read, Search, Edit or Run as they work.")
                    .font(.callout).foregroundStyle(.tertiary)
            } else {
                roster
            }
        }
    }

    /// Working agents first, then finished ones, newest finish first.
    private var ordered: [AgentRun] {
        agents.filter { !$0.state.isFinished } + agents.filter { $0.state.isFinished }.sorted { $0.finishOrder > $1.finishOrder }
    }

    private var roster: some View {
        VStack(spacing: 8) {
            ForEach(ordered) { run in AgentRow(run: run, selected: selected == run.id) { selected = selected == run.id ? nil : run.id } }
        }
    }
}

// MARK: Canvas

private struct AgentCanvas: View {
    @Bindable var conversation: Conversation
    @Binding var selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = !reduceMotion
        let live = animate && (conversation.isRunning || AgentLayout.needsAnimation(conversation.agents))
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !live)) { tl in
            canvas(now: tl.date, animate: animate)
        }
        .frame(height: AgentLayout.height)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)           // the roster below carries the same information for VoiceOver
    }

    private func canvas(now: Date, animate: Bool) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let agents = conversation.agents
            let pos = AgentLayout.positions(agents, now: now, animate: animate, in: size)
            let hub = AgentLayout.hub(in: size)
            let crowded = agents.count > 8
            ZStack {
                ForEach(AgentZone.allCases.filter { $0 != .hub }, id: \.self) { z in zone(z, size: size, agents: agents) }
                links(agents, pos: pos, hub: hub, now: now, animate: animate)
                HubBot(running: conversation.isRunning, now: now, animate: animate).position(hub)
                ForEach(agents) { run in
                    BotView(run: run, selected: selected == run.id, bubble: !crowded || selected == run.id, now: now, animate: animate)
                        .position(pos[run.id] ?? hub)
                        .onTapGesture { selected = selected == run.id ? nil : run.id }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func zone(_ z: AgentZone, size: CGSize, agents: [AgentRun]) -> some View {
        let r = AgentLayout.zoneRect(z, in: size)
        let busy = z != .rest && agents.contains { !$0.state.isFinished && $0.zone == z }
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(busy ? 0.07 : 0.035))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(busy ? HTB.green.opacity(0.35) : Color.white.opacity(0.07)))
            .overlay(alignment: z == .rest ? .topTrailing : .topLeading) {
                Text(z.label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(busy ? HTB.green : Color.secondary.opacity(0.8))
                    .padding(.horizontal, 8).padding(.top, 5)
            }
            .frame(width: r.width - 4, height: r.height - 4)
            .position(x: r.midX, y: r.midY)
    }

    private func links(_ agents: [AgentRun], pos: [String: CGPoint], hub: CGPoint, now: Date, animate: Bool) -> some View {
        Canvas { ctx, _ in
            let phase = animate ? CGFloat((now.timeIntervalSinceReferenceDate * 14).truncatingRemainder(dividingBy: 20)) : 0
            for a in agents where !a.state.isFinished {
                guard let to = pos[a.id] else { continue }
                let from = a.parentID.flatMap { pos[$0] } ?? hub
                var p = Path(); p.move(to: from); p.addLine(to: to)
                ctx.stroke(p, with: .color(HTB.green.opacity(0.3)), style: StrokeStyle(lineWidth: 1.1, dash: [4, 4], dashPhase: -phase))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Bots

private struct Eyes: View {
    let state: AgentState
    let color: Color
    let look: CGFloat
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { _ in
                switch state {
                case .done, .stopped: Capsule().fill(color).frame(width: 5, height: 1.6)
                case .failed: Image(systemName: "xmark").font(.system(size: 5, weight: .black)).foregroundStyle(color)
                default: Circle().fill(color).frame(width: 4.2, height: 4.2).offset(x: look)
                }
            }
        }
    }
}

private struct BotView: View {
    let run: AgentRun
    let selected: Bool
    let bubble: Bool
    let now: Date
    let animate: Bool

    var body: some View {
        let c = agentTint(run)
        let t = animate ? now.timeIntervalSinceReferenceDate : 0
        let working = !run.state.isFinished
        let pulse = working && animate ? 0.55 + 0.45 * abs(sin(t * 3)) : 1
        VStack(spacing: 2) {
            if bubble, working, !run.activity.isEmpty {
                Text(run.activity).font(.system(size: 9.5)).lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 6).padding(.vertical, 2).frame(maxWidth: 104)
                    .background(HTB.panel.opacity(0.95), in: Capsule())
                    .overlay(Capsule().strokeBorder(c.opacity(0.5)))
                    .transition(.opacity)
            }
            ZStack(alignment: .top) {
                Capsule().fill(c.opacity(0.6)).frame(width: 1.5, height: 6).offset(y: -5)
                Circle().fill(c).frame(width: 4, height: 4).opacity(pulse).offset(y: -8)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.opacity(run.state.isFinished ? 0.14 : 0.24))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(c.opacity(selected ? 1 : 0.7), lineWidth: selected ? 2 : 1))
                    .frame(width: 26, height: 21)
                    .overlay { Eyes(state: run.state, color: c, look: animate ? CGFloat(sin(t * 1.3)) * 1.2 : 0) }
            }
            .padding(.top, 8)
            if !run.state.isFinished || selected {
                Text(run.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 80)
            }
        }
        .opacity(run.state.isFinished ? 0.75 : 1)
        .contentShape(Rectangle())
        .help("\(run.name): \(stateWord(run))")
    }
}

private struct HubBot: View {
    let running: Bool
    let now: Date
    let animate: Bool

    var body: some View {
        let t = animate ? now.timeIntervalSinceReferenceDate : 0
        VStack(spacing: 2) {
            ZStack {
                if running { Circle().stroke(HTB.green.opacity(animate ? 0.5 - 0.3 * abs(sin(t * 2)) : 0.3), lineWidth: 2).frame(width: 52, height: 52) }
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HTB.green.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HTB.green))
                    .frame(width: 38, height: 30)
                    .overlay { Text("^ ^").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(HTB.green) }
            }
            Text("Claude").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(HTB.green)
        }
    }
}

// MARK: Roster

private struct AgentRow: View {
    let run: AgentRun
    let selected: Bool
    let tap: () -> Void

    private var stats: String {
        var p: [String] = []
        if run.toolUses > 0 { p.append("\(run.toolUses) tool\(run.toolUses == 1 ? "" : "s")") }
        if run.tokens > 0 { p.append("\(compact(run.tokens)) tokens") }
        return p.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: tap) {
                HStack(alignment: .top, spacing: 10) {
                    PulseDot(color: agentTint(run), pulsing: !run.state.isFinished).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(run.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            if run.parentID != nil { Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary) }
                        }
                        Text(run.state.isFinished ? stats.isEmpty ? stateWord(run) : "\(stateWord(run)) · \(stats)" : (run.activity.isEmpty ? stateWord(run) : run.activity))
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(selected ? 3 : 1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        if run.state.isFinished { Text(clock(run.elapsed)) } else { Text(run.startedAt, style: .timer).monospacedDigit() }
                        Text(run.type).foregroundStyle(.tertiary).lineLimit(1)
                    }.font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            if selected { detail }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? agentTint(run).opacity(0.6) : .clear))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(run.name), \(run.type) agent, \(stateWord(run)). \(run.activity)")
    }

    @ViewBuilder private var detail: some View {
        if !run.prompt.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Task").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                Text(run.prompt).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(6)
            }
        }
        if !run.steps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                ForEach(run.steps.suffix(12)) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        switch s.state {
                        case .running: Text("›").foregroundStyle(HTB.cyan)
                        case .done: Text("✓").foregroundStyle(HTB.green)
                        case .failed: Text("✕").foregroundStyle(HTB.red)
                        }
                        Text(s.title).foregroundStyle(.primary.opacity(0.85))
                        Text(s.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }.font(.system(size: 11, design: .monospaced))
                }
            }
        }
        if let r = run.report, !r.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Report").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                MarkdownView(text: String(r.prefix(3_000))).font(.system(size: 12))
            }
        }
    }
}
