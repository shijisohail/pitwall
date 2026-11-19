import SwiftUI
import AppKit

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Binding var inspectorOpen: Bool
    @Environment(Store.self) private var store
    @Bindable private var settings = AppSettings.shared
    @State private var chatHeight: CGFloat = 800
    /// True while the transcript end is in view. Streaming output only follows the end while pinned, so scrolling up to read is never fought.
    @State private var pinned = true
    @State private var lastContentHeight: CGFloat = 0

    private var scrollToken: Int {
        let last = conversation.messages.last?.blocks.last
        return conversation.messages.count &* 1_000_003 &+ (last?.text.count ?? 0) &+ (last?.inputJSON.count ?? 0)
            &+ (last?.result?.count ?? 0) &+ (conversation.isRunning ? 1 : 0) &+ conversation.approvals.count &* 7
    }

    private struct ScrollEnd: Equatable { var distance: CGFloat; var height: CGFloat }

    private func follow(_ proxy: ScrollViewProxy) {
        if pinned { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func jump(_ proxy: ScrollViewProxy, animated: Bool = false) {
        pinned = true
        if animated { withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var meta: String {
        let model = store.catalog(conversation.cwd).models.first { $0.value == conversation.model }?.name ?? conversation.model
        return [conversation.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"), conversation.branch, model, conversation.permission.label]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if conversation.loadState == .loading {
                            ProgressView("Loading history…").frame(maxWidth: .infinity).padding(.top, 60)
                        } else if conversation.messages.isEmpty {
                            EmptyState(conversation: conversation)
                        }
                        let shown = conversation.messages.filter { !$0.blocks.isEmpty }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                            MessageView(message: m, live: conversation.isRunning && i == shown.count - 1, cwd: conversation.cwd)
                        }
                        if conversation.isRunning, conversation.approvals.isEmpty, conversation.messages.last?.role != .assistant { Shimmer() }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 24)
                }
                .defaultScrollAnchor(.bottom)
                // Content growing under a pinned view is not the user leaving the end; only an offset change at a steady height is.
                .onScrollGeometryChange(for: ScrollEnd.self) {
                    // containerSize already excludes the bottom inset (the composer), so none is added here.
                    ScrollEnd(distance: $0.contentSize.height - ($0.contentOffset.y + $0.containerSize.height),
                              height: $0.contentSize.height)
                } action: { _, e in
                    defer { lastContentHeight = e.height }
                    guard e.height == lastContentHeight else { return }
                    if e.distance > 60 { pinned = false } else if e.distance < 24 { pinned = true }
                }
                .onChange(of: scrollToken) { follow(proxy) }
                .onChange(of: conversation.loadState) { jump(proxy) }
                // Sending a message always returns to the end.
                .onChange(of: conversation.messages.count) { if conversation.messages.last?.role == .user { jump(proxy) } }
                // The area under the chat grows when a task or a side answer appears or the Tasks bar opens: keep the end in view.
                .onChange(of: conversation.tasks.count) { follow(proxy) }
                .onChange(of: conversation.tasksExpanded) { follow(proxy) }
                .onChange(of: conversation.workflows.count) { follow(proxy) }
                .onChange(of: conversation.sideQA.count) { follow(proxy) }
                .overlay(alignment: .bottom) {
                    if !pinned {
                        Button { jump(proxy, animated: true) } label: {
                            Label(conversation.isRunning ? "Latest" : "Jump to latest", systemImage: "arrow.down")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .buttonStyle(HTBSecondary())
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityLabel("Scroll to latest message")
                    }
                }
                .animation(.snappy(duration: 0.2), value: pinned)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if conversation.externallyActive { LiveBanner(conversation: conversation) }
                    if let r = conversation.retryNote { Text(r).font(.caption).foregroundStyle(.orange) }
                    SideAnswers(conversation: conversation)
                    WorkflowsBar(conversation: conversation)
                    TasksBar(conversation: conversation)
                    RunningBar(conversation: conversation)
                    ApprovalStack(conversation: conversation)
                    Composer(conversation: conversation)
                }
                .frame(maxWidth: 760).padding(.horizontal, 26).padding(.bottom, 16).padding(.top, 24).frame(maxWidth: .infinity)
                // Dark and frosted, so the transcript scrolling underneath blurs behind the bars and the prompt box instead of cluttering them.
                .background(alignment: .top) {
                    Rectangle().fill(HTB.bg.opacity(0.62)).background(.ultraThinMaterial)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .frame(minWidth: 480)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chatHeight = $0 }
        // A card taller than the window would push its own buttons off-screen, so cards scroll inside this cap.
        .environment(\.approvalMaxHeight, max(220, chatHeight * 0.6))
        .attachmentDrop(for: conversation)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title).font(.system(size: 16, weight: .semibold, design: .monospaced)).lineLimit(1)
                Text(meta).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let w = conversation.worktreeLabel { worktreePill(w) }
            if conversation.contextTokens > 0 || conversation.cost > 0 { statusPill }
            Button { conversation.openInTerminal() } label: { Image(systemName: "terminal") }
                .buttonStyle(HTBSecondary(circle: true)).help("Continue this session in Terminal (⇧⌘T)").accessibilityLabel("Open in Terminal")
                .disabled(conversation.isRunning)
            Button { withAnimation(.snappy(duration: 0.25)) { inspectorOpen.toggle() } } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(HTBSecondary(circle: true)).help(inspectorOpen ? "Hide inspector" : "Show inspector").accessibilityLabel("Toggle inspector")
            actions
        }
        .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 10)
    }

    /// Edits from this session land in a separate checkout, not in the project folder: always say so.
    private func worktreePill(_ name: String) -> some View {
        Label(name, systemImage: "arrow.triangle.branch")
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(HTB.cyan).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 7).panel(RoundedRectangle(cornerRadius: 8))
            .help(conversation.inWorktree
                  ? "This session works in its own git worktree, so its edits don't touch the main checkout. Branch worktree-\(name)."
                  : "This session will start in its own git worktree (worktree-\(name)) when you send the first message.")
            .accessibilityLabel("Worktree \(name)")
    }

    private var statusPill: some View {
        let pct = min(100, conversation.contextTokens * 100 / max(conversation.contextWindow, 1))
        return Text("ctx \(pct)%" + (conversation.cost > 0 ? " · " + String(format: "$%.2f", conversation.cost) : ""))
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 12).padding(.vertical, 7).panel(RoundedRectangle(cornerRadius: 8))
            .help("\(conversation.contextTokens / 1000)k of \(conversation.contextWindow / 1000)k tokens")
    }

    private var actions: some View {
        Menu {
            Section("Session") {
                Button("Compact Conversation") { conversation.send("/compact") }.disabled(conversation.isRunning)
                Button("Show Context Usage") { conversation.send("/context") }.disabled(conversation.isRunning)
                Button("Show Plan Usage") { conversation.send("/usage") }.disabled(conversation.isRunning)
                Button("Fork Session") { store.fork(conversation) }
                Button("Rename…") { conversation.promptRename() }
                Button("Export as Markdown…") { conversation.exportMarkdown(to: "") }
            }
            Section("Inspect") {
                Button("Review All Uncommitted Changes") { store.sheet = .diff }
                Button("MCP Servers…") { store.sheet = .mcp }
                Button("Memory Files…") { store.sheet = .memory }
                Button("Permissions…") { store.sheet = .config("permissions") }
                Button("Hooks…") { store.sheet = .config("hooks") }
                Button("Status…") { store.sheet = .status }
                Button("All Commands & Skills…") { store.sheet = .commands }
            }
            if conversation.canChooseWorktree || conversation.inWorktree {
                Section("Worktree") {
                    if conversation.canChooseWorktree {
                        Toggle("Run in Own Worktree", isOn: Binding(get: { conversation.worktreeName != nil }, set: { _ in conversation.toggleWorktree() }))
                    }
                    if conversation.inWorktree {
                        Button("Reveal Worktree in Finder") { conversation.revealWorktree() }
                        Button("Remove Worktree…", role: .destructive) { conversation.removeWorktree() }.disabled(conversation.isRunning)
                    }
                }
            }
            Section("View") {
                Toggle("Agent View", isOn: $settings.showAgents)
            }
            Section {
                Button("Copy Session ID") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(conversation.sessionID ?? conversation.id, forType: .string)
                }
                if let p = conversation.historyPath {
                    Button("Reveal Transcript in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                }
            }
        } label: { Image(systemName: "ellipsis").accessibilityLabel("Session actions") }
        .menuStyle(.button).buttonStyle(HTBSecondary(circle: true)).fixedSize()
    }
}

struct LiveBanner: View {
    let conversation: Conversation
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            PulseDot(color: .orange, pulsing: true)
            Text("Live in a terminal. This view updates automatically.").font(.callout)
            Spacer()
            Button("Fork & Continue Here") { store.fork(conversation) }.buttonStyle(HTBSecondary()).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .panel(RoundedRectangle(cornerRadius: 8), tint: HTB.amber.opacity(0.10), border: HTB.amber.opacity(0.5))
    }
}

struct EmptyState: View {
    let conversation: Conversation

    private let ideas: [(String, String, String, String)] = [
        ("magnifyingglass", "Explain this codebase", "Map the architecture and entry points.", "Give me a tour of this codebase: architecture, key modules and entry points."),
        ("checkmark.seal", "Fix failing tests", "Run the suite, find the cause, patch it.", "Run the test suite, find why anything fails, and fix it."),
        ("map", "Plan a feature", "Think first, no edits until you say so.", "/plan"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 34, weight: .light))
                .frame(width: 84, height: 84).panel(RoundedRectangle(cornerRadius: 16), tint: HTB.green.opacity(0.08), border: HTB.green.opacity(0.5))
            Text("What are we building in \((conversation.cwd as NSString).lastPathComponent)?")
                .font(.system(size: 26, weight: .semibold)).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(ideas, id: \.1) { icon, title, sub, prompt in
                    Button { conversation.send(prompt) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon).foregroundStyle(.tint).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).fontWeight(.semibold)
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: 420, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).glassCard(16)
                }
            }
            Text("Type / for commands, @ for files, ! to run a shell command").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }
}
