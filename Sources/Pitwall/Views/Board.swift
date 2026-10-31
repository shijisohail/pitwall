import SwiftUI

struct BoardView: View {
    @Environment(Store.self) private var store

    private var needs: [Conversation] {
        store.conversations.filter { !$0.approvals.isEmpty && inScope($0) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var working: [Conversation] {
        store.conversations.filter { $0.approvals.isEmpty && ($0.isRunning || $0.externallyActive) && inScope($0) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var recent: [Conversation] {
        let day = Date().addingTimeInterval(-86_400)
        let idle = store.filtered.filter { inScope($0) }.filter {
            $0.approvals.isEmpty && !$0.isRunning && !$0.externallyActive && ($0.historyPath != nil || !$0.messages.isEmpty)
        }
        let today = idle.filter { $0.updatedAt > day }
        return Array((today.isEmpty ? idle : today).prefix(14))
    }

    private func inScope(_ c: Conversation) -> Bool {
        guard let o = store.owner(c) else { return false }
        return store.focusProject == nil || store.focusProject == o
    }

    private var summary: String {
        let active = needs.count + working.count
        let projects = Set((needs + working).map(\.cwd)).count
        if active == 0 { return "Nothing running. Start something or pick up where you left off." }
        return "\(active) active across \(projects) project\(projects == 1 ? "" : "s")" + (needs.isEmpty ? "" : " · \(needs.count) need you")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            projectChips
            HStack(alignment: .top, spacing: 16) {
                column("Working", HTB.green, working, pulse: true, empty: "Nothing is running right now.")
                column("Needs you", HTB.amber, needs, pulse: false, empty: "No approvals or questions waiting.")
                column(recentTitle, .gray, recent, pulse: false, empty: "No sessions yet. Open a project to begin.")
            }
        }
        .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 20)
    }

    private var recentTitle: String { recent.allSatisfy { $0.updatedAt > Date().addingTimeInterval(-86_400) } ? "Done today" : "Recent" }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PIT_WALL").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(HTB.green).tracking(1)
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.sheet = .switcher } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("Search sessions and prompts").foregroundStyle(.secondary)
                    Spacer(minLength: 20)
                    Text("⌘K").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9).frame(width: 300)
            }.buttonStyle(.plain).panel(RoundedRectangle(cornerRadius: 8))
            if let u = store.usage { UsageMini(usage: u) }
            Menu {
                Button("New session in current project") { store.newConversation() }
                Divider()
                ForEach(store.projects.prefix(8)) { p in Button(p.name) { store.newConversation(cwd: p.path) } }
                Divider()
                Button("Open Project…") { store.sheet = .projects }
            } label: { Label("New session", systemImage: "plus").padding(.horizontal, 6) }
                .menuStyle(.button).buttonStyle(HTBPrimary()).controlSize(.large).fixedSize()
        }
    }

    private var projectChips: some View {
        HStack(spacing: 8) {
            chip("All projects", nil)
            ForEach(store.projects) { p in chip(p.name, p.path) }
            Button { store.sheet = .projects } label: { Label("Open project", systemImage: "plus").font(.system(size: 12.5)) }
                .buttonStyle(HTBSecondary()).controlSize(.small)
            Spacer()
        }
    }

    @ViewBuilder private func chip(_ title: String, _ path: String?) -> some View {
        let on = store.focusProject == path
        Button { store.focusProject = path } label: { Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular)) }
            .buttonStyle(HTBChip(on: on))
            .contextMenu { if let path { Button("Close Project") { store.closeFolder(path) } } }
    }

    private func column(_ title: String, _ color: Color, _ items: [Conversation], pulse: Bool, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PulseDot(color: color, pulsing: pulse && !items.isEmpty)
                Text("\(title) · \(items.count)").font(.system(size: 12, weight: .semibold)).textCase(.uppercase).tracking(0.7)
                    .foregroundStyle(color == .gray ? Color.secondary : color)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if items.isEmpty {
                        Text(empty).font(.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    ForEach(items) { SessionCard(c: $0) }
                }
            }.scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: pulsing ? color : .clear, radius: 5)
            .opacity(pulsing && on ? 0.35 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever() : .default, value: on)
            .onAppear { on = true }
            .onChange(of: pulsing) { _, p in on = false; if p { DispatchQueue.main.async { on = true } } }
    }
}

struct UsageMini: View {
    let usage: Usage
    var body: some View {
        HStack(spacing: 10) {
            bar("5h", usage.fiveHour, HTB.green)
            bar("7d", usage.sevenDay, HTB.cyan)
        }
        .padding(.horizontal, 14).padding(.vertical, 9).panel(RoundedRectangle(cornerRadius: 8))
        .help("Plan usage: 5-hour window \(Int(usage.fiveHour * 100))%, 7-day \(Int(usage.sevenDay * 100))%")
    }
    private func bar(_ t: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Text(t).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Capsule().fill(.white.opacity(0.14)).frame(width: 60, height: 5).overlay(alignment: .leading) {
                Capsule().fill(v > 0.85 ? Color.red : c).frame(width: max(5, 60 * min(v, 1)))
            }
        }
    }
}

struct SessionCard: View {
    let c: Conversation
    @Environment(Store.self) private var store

    private var live: Bool { c.isRunning || c.externallyActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((c.cwd as NSString).lastPathComponent).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(.white.opacity(0.09), in: Capsule())
                Spacer()
                meta
            }
            Text(c.title).font(.system(size: 15.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
            if let a = c.approvals.first { approval(a) }
            else if live { liveBody }
            else { doneBody }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18, tint: c.approvals.isEmpty ? nil : .orange.opacity(0.16))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { store.open(c) }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if c.isRunning, let t = c.turnStart { Text(t, style: .timer).monospacedDigit() }
            else if c.externallyActive { Text("in terminal") }
            else { Text(relativeTime(c.updatedAt)) }
            if c.cost > 0 { Text("· " + String(format: "$%.2f", c.cost)) }
        }
        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
    }

    // MARK: Working

    @ViewBuilder private var liveBody: some View {
        let feed = c.feed
        if !feed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(feed) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        switch l.state {
                        case .done: Text("✓").foregroundStyle(HTB.green)
                        case .running: Text("›").foregroundStyle(HTB.cyan)
                        case .failed: Text("✕").foregroundStyle(.red)
                        case .text: EmptyView()
                        }
                        if !l.title.isEmpty { Text(l.title).foregroundStyle(.primary.opacity(0.85)) }
                        Text(l.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 12))
        }
        if let p = c.todoProgress {
            ProgressView(value: Double(p.done), total: Double(p.total)).tint(HTB.green)
            Text("\(p.done) of \(p.total) steps").font(.caption2).foregroundStyle(.tertiary)
        } else if c.isRunning {
            ProgressView().progressViewStyle(.linear).tint(HTB.green)
        }
    }

    // MARK: Needs you

    @ViewBuilder private func approval(_ a: Approval) -> some View {
        switch a.kind {
        case .tool:
            Text("Claude wants to use **\(a.tool)**").font(.callout).foregroundStyle(.secondary)
            Text(a.tool == "Bash" ? "$ " + (a.input["command"] as? String ?? "") : toolBlock(a).toolSummary)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange).lineLimit(3)
                .help(a.tool == "Bash" ? (a.input["command"] as? String ?? "") : "")
                .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 8) {
                Button("Allow") { c.allow(a) }.buttonStyle(HTBPrimary())
                if let s = a.suggestions.first { Button("Always") { c.allow(a, remember: s) }.buttonStyle(HTBSecondary()).help(suggestionLabel(s)) }
                Button("Deny") { c.deny(a) }.buttonStyle(HTBSecondary(color: HTB.red))
            }.controlSize(.small)
            if let s = a.suggestions.first {
                Text("Always = \(suggestionLabel(s))").font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        case .question:
            let qs = a.input["questions"] as? [[String: Any]] ?? []
            let q = qs.first
            let opts = (q?["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            let simple = qs.count == 1 && (q?["multiSelect"] as? Bool) != true
            Text(q?["question"] as? String ?? "Claude has a question").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                if simple {
                    ForEach(opts, id: \.self) { o in
                        Button(o) { c.allow(a, input: ["questions": qs, "answers": [q?["question"] as? String ?? "": o]]) }.buttonStyle(HTBSecondary())
                    }
                }
                Button(simple ? "Other…" : "Answer…") { store.open(c) }.buttonStyle(HTBSecondary())
            }.controlSize(.small)
        case .plan:
            Text("A plan is ready for review").font(.callout).foregroundStyle(.secondary)
            Button("Review plan") { store.open(c) }.buttonStyle(HTBPrimary()).controlSize(.small)
        }
    }

    private func toolBlock(_ a: Approval) -> Block {
        var b = Block(kind: .tool); b.toolName = a.tool
        if let d = try? JSONSerialization.data(withJSONObject: a.input) { b.inputJSON = String(decoding: d, as: UTF8.self) }
        return b
    }

    // MARK: Done

    @ViewBuilder private var doneBody: some View {
        let s = c.diffStat
        HStack(spacing: 6) {
            if s.files > 0 {
                Text("\(s.files) file\(s.files == 1 ? "" : "s") changed").foregroundStyle(.secondary)
                Text("+\(s.added)").foregroundStyle(.green)
                Text("−\(s.removed)").foregroundStyle(.red)
            } else if let b = c.branch {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.tertiary)
                Text(b).foregroundStyle(.secondary)
            }
        }.font(.system(size: 12.5, design: .monospaced))
    }
}
