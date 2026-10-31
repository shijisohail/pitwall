import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Rail()
            VStack(spacing: 0) {
                if store.cliStatus == .missing { CLIMissingBanner() }
                if !store.workspace.isEmpty { TabBar() }
                Group {
                    if store.workspace.isEmpty { Welcome() }
                    else if store.showBoard { BoardView() }
                    else if let c = store.current { SessionScreen(conversation: c).id(c.id) }
                    else { BoardView() }
                }
            }
        }
        .background { AuroraBackground() }
        .dropDestination(for: URL.self) { urls, _ in store.openDropped(urls) }
        .sheet(item: $store.sheet) { SheetHost(kind: $0) }
        .environment(\.openURL, OpenURLAction { LinkPolicy.allows($0) ? .systemAction : .discarded })
        .task { await store.checkCLI() }
        .task {
            await store.scan()
            // Pick up sessions started or changed in a terminal.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                await store.scan()
            }
        }
    }
}

/// B: session list · chat · inspector.
struct SessionScreen: View {
    @Bindable var conversation: Conversation
    @AppStorage("inspectorOpen") private var inspectorOpen = true

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                SessionList()
                divider
                ChatView(conversation: conversation, inspectorOpen: $inspectorOpen)
                if inspectorOpen && g.size.width > 1150 {
                    divider
                    InspectorView(conversation: conversation).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
}

struct Rail: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            Color.clear.frame(height: 34)          // room for the traffic lights
            item("square.grid.2x2", "Pit Wall (⌘1)", active: store.showBoard) { store.showBoard = true }
            item("bubble.left.and.bubble.right", "Sessions (⌘2)", active: !store.showBoard) { showSessions() }
            item("magnifyingglass", "Search all sessions (⌘K)", active: false) { store.sheet = .switcher }
            Spacer()
            item("folder.badge.plus", "Open or close projects (⌘O chooses a folder)", active: false) { store.sheet = .projects }
            item("command", "Commands & skills", active: false) { store.sheet = .commands }
        }
        .padding(.vertical, 14).frame(width: 68)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
    }

    private func showSessions() {
        if store.current == nil { store.selection = store.filtered.first?.id }
        store.showBoard = false
    }

    private func item(_ icon: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 42, height: 42)
                .background(active ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

/// Shown until the `claude` CLI is found: Pitwall can't do anything without it.
struct CLIMissingBanner: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HTB.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code wasn't found").fontWeight(.semibold)
                Text("Pitwall drives the `claude` command-line tool. Install it, or point Pitwall at it.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install Instructions") { NSWorkspace.shared.open(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!) }.buttonStyle(HTBSecondary())
            Button("Choose…") { choose() }.buttonStyle(HTBSecondary())
            Button("Retry") { Task { await store.checkCLI() } }.buttonStyle(HTBPrimary())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(HTB.amber.opacity(0.10))
        .overlay(alignment: .bottom) { Rectangle().fill(HTB.amber.opacity(0.5)).frame(height: 1) }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.message = "Choose the claude executable"; p.prompt = "Use This"
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin")
        guard p.runModal() == .OK, let url = p.url else { return }
        AppSettings.shared.claudePath = url.path
        Task { await store.checkCLI() }
    }
}
