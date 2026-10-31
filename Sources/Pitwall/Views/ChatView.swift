import SwiftUI
import AppKit

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Binding var inspectorOpen: Bool
    @Environment(Store.self) private var store

    private var scrollToken: Int {
        let last = conversation.messages.last?.blocks.last
        return conversation.messages.count &* 1_000_003 &+ (last?.text.count ?? 0) &+ (last?.inputJSON.count ?? 0)
            &+ (last?.result?.count ?? 0) &+ (conversation.isRunning ? 1 : 0) &+ conversation.approvals.count &* 7
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
                .onChange(of: scrollToken) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversation.loadState) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if conversation.externallyActive { LiveBanner(conversation: conversation) }
                    if let r = conversation.retryNote { Text(r).font(.caption).foregroundStyle(.orange) }
                    ApprovalStack(conversation: conversation)
                    Composer(conversation: conversation)
                }
                .frame(maxWidth: 760).padding(.horizontal, 26).padding(.bottom, 16).frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 480)
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
