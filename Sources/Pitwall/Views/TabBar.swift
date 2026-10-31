import SwiftUI

/// Browser-style tabs: Pit Wall is pinned first, then one tab per open session.
struct TabBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            boardTab
            Rectangle().fill(HTB.border).frame(width: 1, height: 18).padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(store.tabs, id: \.self) { id in
                        if let c = store.conversations.first(where: { $0.id == id }) {
                            TabItem(c: c, active: !store.showBoard && store.selection == id)
                        }
                    }
                }
            }
            Button { store.newConversation() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("New tab (⌘T)").accessibilityLabel("New tab")
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background(HTB.bg.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(HTB.border).frame(height: 1) }
    }

    private var boardTab: some View {
        Button { store.showBoard = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2").font(.system(size: 12, weight: .semibold))
                Text("BOARD").font(.system(size: 11.5, weight: .bold, design: .monospaced)).tracking(0.8)
            }
            .foregroundStyle(store.showBoard ? HTB.green : Color.secondary)
            .padding(.horizontal, 12).frame(height: 40)
            .background(store.showBoard ? HTB.panel : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(store.showBoard ? HTB.green : .clear).frame(height: 2) }
        }.buttonStyle(.plain).help("Pit Wall (⌘1)")
    }
}

private struct TabItem: View {
    let c: Conversation
    let active: Bool
    @Environment(Store.self) private var store
    @State private var hover = false

    private var dot: Color { !c.approvals.isEmpty ? HTB.amber : c.isRunning ? HTB.green : (c.externallyActive ? HTB.amber : Color.secondary.opacity(0.45)) }

    var body: some View {
        HStack(spacing: 8) {
            PulseDot(color: dot, pulsing: c.isRunning || !c.approvals.isEmpty)
            Text(c.title).font(.system(size: 12, design: .monospaced)).lineLimit(1).frame(maxWidth: 170, alignment: .leading)
                .foregroundStyle(active ? Color.primary : Color.secondary)
            Button { store.closeTab(c.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
                    .background(hover ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }.buttonStyle(.plain).foregroundStyle(.secondary).opacity(active || hover ? 1 : 0.35)
                .accessibilityLabel("Close tab \(c.title)")
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(active ? HTB.panel : (hover ? Color.white.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(active ? HTB.green : .clear).frame(height: 2) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.selectTab(c.id) }
        .draggable(c.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            store.moveTab(id, before: c.id); return true
        }
        .contextMenu {
            Button("Close Tab") { store.closeTab(c.id) }
            Button("Close Other Tabs") { store.closeOtherTabs(c.id) }.disabled(store.tabs.count < 2)
            Button("Close Tabs to the Right") { store.closeTabs(after: c.id) }
            Divider()
            Button("Open in Terminal") { c.openInTerminal() }
            Button("Fork") { store.fork(c) }.disabled(c.sessionID == nil)
        }
        .help(c.title)
    }
}
