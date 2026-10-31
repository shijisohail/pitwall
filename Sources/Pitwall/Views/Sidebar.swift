import SwiftUI
import AppKit

/// Narrow session list shown beside the chat: grouped by project, with status dots.
struct SessionList: View {
    @Environment(Store.self) private var store
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search chats", text: $store.query).textFieldStyle(.plain).font(.system(size: 13))
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).panel(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12).padding(.top, 44).padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.projects) { p in project(p) }
                    if store.filtered.isEmpty { Text(store.query.isEmpty ? "No sessions yet" : "No matches").font(.callout).foregroundStyle(.tertiary).padding(12) }
                }.padding(.horizontal, 8)
            }.scrollIndicators(.hidden)

            footer
        }
        .frame(width: 236)
    }

    private func project(_ p: Project) -> some View {
        let all = store.conversations(in: p)
        let showAll = expanded.contains(p.id) || !store.query.isEmpty
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(p.name).font(.system(size: 11, weight: .bold, design: .monospaced)).textCase(.uppercase).tracking(0.6).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { store.newConversation(cwd: p.path) } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("New session in \(p.name)")
                Menu {
                    Button("New Session") { store.newConversation(cwd: p.path) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.path)]) }
                    Divider()
                    Button("Close Project") { store.closeFolder(p.path) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)) }
                    .menuStyle(.button).buttonStyle(.plain).foregroundStyle(.secondary).fixedSize()
            }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
            ForEach(showAll ? all : Array(all.prefix(5))) { SessionRow(c: $0) }
            if !showAll && all.count > 5 {
                Button("Show all \(all.count)") { expanded.insert(p.id) }.buttonStyle(.plain).font(.caption)
                    .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 4)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if store.isScanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading history…").font(.caption) }.foregroundStyle(.secondary)
            }
            if let u = store.usage { UsageCard(usage: u) }
            HStack {
                Menu {
                    @Bindable var s = store
                    Toggle("Show script / SDK sessions (\(store.hiddenAutomationCount))", isOn: $s.showAutomation)
                    Button("Search All Sessions…") { store.sheet = .switcher }
                    Button("Refresh") { Task { await store.scan() } }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .menuStyle(.button).buttonStyle(.plain).foregroundStyle(.secondary).fixedSize()
                Text("\(store.filtered.count) sessions").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct UsageCard: View {
    let usage: Usage

    var body: some View {
        VStack(spacing: 9) {
            bar("5-hour window", usage.fiveHour, usage.fiveReset)
            bar("7-day", usage.sevenDay, usage.sevenReset)
        }
        .padding(12).glassCard(16)
    }

    private func bar(_ title: String, _ v: Double, _ reset: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((v * 100).rounded()))%").font(.system(.caption, design: .monospaced).weight(.semibold))
            }
            Capsule().fill(.white.opacity(0.12)).frame(height: 6).overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(LinearGradient(colors: [HTB.green, v > 0.85 ? HTB.red : HTB.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, g.size.width * min(v, 1)))
                }
            }.frame(height: 6)
            if let reset { Text("resets \(reset, format: .relative(presentation: .named))").font(.caption2).foregroundStyle(.tertiary) }
        }
    }
}

private struct SessionRow: View {
    let c: Conversation
    @Environment(Store.self) private var store

    private var dot: Color { !c.approvals.isEmpty ? HTB.amber : c.isRunning ? HTB.green : (c.externallyActive ? HTB.amber : Color.secondary.opacity(0.4)) }

    var body: some View {
        let selected = store.selection == c.id
        let live = c.isRunning || c.externallyActive || !c.approvals.isEmpty
        Button { store.open(c) } label: {
            HStack(spacing: 10) {
                PulseDot(color: dot, pulsing: live)
                Text(c.title).lineLimit(1).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                Spacer(minLength: 4)
                Text(relativeTime(c.updatedAt)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") { c.promptRename() }
            Button("Fork") { Store.shared.fork(c) }.disabled(c.sessionID == nil)
            Button("Open in Terminal") { c.openInTerminal() }
            if let p = c.historyPath {
                Button("Reveal Transcript in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
            }
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.sessionID ?? c.id, forType: .string)
            }
            if c.historyPath == nil { Button("Remove", role: .destructive) { Store.shared.remove(c) } }
        }
    }
}
