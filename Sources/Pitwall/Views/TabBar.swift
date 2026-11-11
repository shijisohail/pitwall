import SwiftUI

/// Browser-style tabs: Pit Wall is pinned first, then one tab per open session.
/// Tab strip height. It shares a row with the window's traffic lights, so it stays slim.
let tabBarHeight: CGFloat = 30

/// The strip height now: the notch row's, in notch full screen, so the tabs fill it exactly.
@MainActor var barHeight: CGFloat { NotchLayout.shared.active ? NotchLayout.shared.height : tabBarHeight }

struct TabBar: View {
    @Environment(Store.self) private var store

    private let notch = NotchLayout.shared
    @State private var strip = StripGeometry()

    var body: some View {
        Group {
            if notch.active { notchRow } else { HStack(spacing: 4) { boardTab; divider; tabs; newTab } }
        }
        .padding(.horizontal, 10).frame(height: barHeight)
        .background(HTB.bg.opacity(0.55)).background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(HTB.border).frame(height: 1) }
    }

    /// Full screen on a notched Mac: tabs fill the row left of the notch and carry on to the right of it, with the +
    /// button at the far right. When there are too many for both sides they shrink to fit instead of scrolling.
    private var notchRow: some View {
        ZStack(alignment: .trailing) {
            NotchFlow(leftEnd: max(0, notch.leftEdge - railWidth - 10 - 14),
                      rightStart: notch.rightEdge - railWidth - 10 + 14, height: notch.height) {
                boardTab
                divider
                ForEach(store.tabs, id: \.self) { id in
                    if let c = store.conversations.first(where: { $0.id == id }) {
                        TabItem(c: c, active: !store.showBoard && store.selection == id)
                    }
                }
            }
            .padding(.trailing, 34).clipped()       // keep the + button's corner clear, however many tabs there are
            newTab
        }
    }

    private var divider: some View { Rectangle().fill(HTB.border).frame(width: 1, height: 14).padding(.horizontal, 4) }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(store.tabs, id: \.self) { id in
                        if let c = store.conversations.first(where: { $0.id == id }) {
                            TabItem(c: c, active: !store.showBoard && store.selection == id).id(id)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tabStrip")) } action: { strip.frames[id] = $0 }
                        }
                    }
                }
                .padding(.trailing, 6)         // so the last tab never sits flush against the + button
            }
            .coordinateSpace(.named("tabStrip"))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { strip.width = $0 }
            // Keep the selected tab fully in view. A bare scrollTo only reveals the nearest edge, which left a new or
            // far-right tab as a sliver beside the + button, where it couldn't be clicked.
            .onAppear { reveal(store.selection, proxy, animated: false) }
            .onChange(of: store.selection) { _, id in reveal(id, proxy) }
            .onChange(of: store.tabs.count) { _, _ in reveal(store.selection, proxy) }
        }
    }

    private func reveal(_ id: String?, _ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))             // let a just-added tab take its place first
            guard let f = strip.frames[id], strip.width > 0 else { return }
            let anchor: UnitPoint? = f.minX < 0 ? .leading : (f.maxX > strip.width ? .trailing : nil)
            guard let anchor else { return }                          // already fully visible: don't move the strip
            if animated { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: anchor) } } else { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    private var newTab: some View {
        Button { store.newConversation() } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 24, height: 24) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("New tab (⌘T)").accessibilityLabel("New tab")
    }

    private var boardTab: some View {
        Button { store.showBoard = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2").font(.system(size: 11, weight: .semibold))
                Text("BOARD").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(0.8)
            }
            .foregroundStyle(store.showBoard ? HTB.green : Color.secondary)
            .padding(.horizontal, 12).frame(height: barHeight)
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
            if c.runningAgentCalls > 1 {
                Label("\(c.runningAgentCalls)", systemImage: "person.2.fill").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.pink)
            }
            Text(c.title).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).frame(maxWidth: 170, alignment: .leading)
                .foregroundStyle(active ? Color.primary : Color.secondary)
            Button { store.closeTab(c.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                    .background(hover ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())      // a plain button only hits its drawn pixels, which for a thin ✕ is almost nothing
            }.buttonStyle(.plain).foregroundStyle(.secondary).opacity(active || hover ? 1 : 0.35)
                .accessibilityLabel("Close tab \(c.title)")
        }
        .padding(.horizontal, 12).frame(height: barHeight)
        .background(active ? HTB.panel : (hover ? Color.white.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(active ? HTB.green : .clear).frame(height: 2) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.selectTab(c.id) }
        .draggable(c.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            store.moveTab(id, onto: c.id); return true
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.title), \(!c.approvals.isEmpty ? "needs your input" : c.isRunning ? "working" : "idle")")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// Lays its children out left to right, hopping over the camera notch: whatever doesn't fit in the span left of the
/// notch continues in the span right of it. The first two children (Pit Wall and its divider) keep their size; the
/// rest shrink evenly when everything won't fit.
private struct NotchFlow: Layout {
    var leftEnd: CGFloat           // where the notch starts, from this layout's left edge
    var rightStart: CGFloat        // where it ends
    var height: CGFloat
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? rightStart + 200, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let capacity = leftEnd + max(0, bounds.width - rightStart)
        var widths = natural
        if natural.reduce(0, +) + gaps > capacity, subviews.count > 2 {
            let fixed = natural[0] + natural[1]
            let share = max(60, (capacity - fixed - gaps) / CGFloat(subviews.count - 2))
            for i in 2..<subviews.count { widths[i] = min(natural[i], share) }
        }
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            if x < leftEnd, x + widths[i] > leftEnd { x = rightStart }       // doesn't fit before the notch: jump over it
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .leading,
                      proposal: ProposedViewSize(width: widths[i], height: bounds.height))
            x += widths[i] + spacing
        }
    }
}

/// Where each tab and the strip's viewport are, so the strip can tell whether the selected tab is fully on screen.
/// A plain class: it is written to while scrolling and must not trigger a redraw.
@MainActor private final class StripGeometry {
    var frames: [String: CGRect] = [:]
    var width: CGFloat = 0
}
