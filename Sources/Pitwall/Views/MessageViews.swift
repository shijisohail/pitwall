import SwiftUI
import AppKit

struct MessageView: View {
    let message: ChatMessage
    let live: Bool
    let cwd: String

    var body: some View {
        switch message.role {
        case .user:
            let parts = message.blocks.map { b -> (notes: [TaskNotification], rest: String) in b.kind == .text ? TaskNotification.split(b.text) : ([], "") }
            let notes = parts.flatMap(\.notes)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) { ForEach(notes) { TaskNotificationRow(note: $0) } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if notes.isEmpty || parts.contains(where: { !$0.rest.isEmpty }) || message.blocks.contains(where: { $0.kind == .image }) {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(message.blocks.enumerated()), id: \.element.id) { i, b in
                        if b.kind == .image, let d = b.imageData, let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else if b.kind == .text, !parts[i].rest.isEmpty {
                            Text(PromptHighlight.sent(parts[i].rest, isKnownCommand: parts[i].rest.hasPrefix("/") ? { isKnownCommand($0, in: Store.shared.catalog(cwd)) } : nil)).textSelection(.enabled).lineSpacing(3)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .panel(RoundedRectangle(cornerRadius: 10), tint: HTB.green.opacity(0.09), border: HTB.green.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 80)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(message.blocks) { b in
                    switch b.kind {
                    case .text: MarkdownView(text: b.text, cwd: cwd)
                    case .thinking: ThinkingView(text: b.text, live: live)
                    case .tool: ToolCard(block: b, live: live)
                    case .notice: NoticeLine(text: b.text)
                    case .output: OutputCard(title: b.toolName, text: b.text)
                    case .local: LocalCard(command: b.toolName, text: b.text, failed: b.isError, live: b.live == true, onStop: { Store.shared.stopLocalShell(messageID: message.id) })
                    case .image: EmptyView()
                    case .error: ErrorCard(text: b.text, cwd: cwd)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A finished background agent, as one quiet line. Click to see the raw notification Claude received.
struct TaskNotificationRow: View {
    let note: TaskNotification
    @State private var open = false

    private var style: (icon: String, color: Color) {
        switch note.status.lowercased() {
        case "completed", "done", "success": ("checkmark.circle.fill", HTB.green)
        case "failed", "error": ("xmark.circle.fill", HTB.red)
        case "killed", "stopped", "cancelled", "canceled": ("stop.circle.fill", HTB.amber)
        default: ("circle.dotted", HTB.cyan)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: style.icon).foregroundStyle(style.color)
                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if !note.detail.isEmpty { Text(note.detail).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 8)
                if let f = note.outputFile, FileManager.default.fileExists(atPath: f) {
                    Button("Log") { Store.shared.openFile(f) }.buttonStyle(HTBSecondary()).controlSize(.small).help("Open the agent's output")
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(Rectangle()).onTapGesture { withAnimation(.snappy(duration: 0.18)) { open.toggle() } }
            if open {
                Text(note.raw).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).glassCard(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Background agent \(note.status): \(note.title). \(note.detail)")
    }
}

struct NoticeLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
        }.padding(.vertical, 4)
    }
}

struct OutputCard: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.isEmpty ? "Output" : title, systemImage: "terminal")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            MarkdownView(text: text)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(16)
    }
}

struct LocalCard: View {
    let command: String
    let text: String
    let failed: Bool
    /// The command is still running: output streams in and it can be stopped.
    var live = false
    var onStop: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right.2").foregroundStyle(.orange)
                Text(command).font(.system(size: 12.5, design: .monospaced)).lineLimit(2)
                Spacer()
                if live {
                    ProgressView().controlSize(.small)
                    if let onStop { Button("Stop", action: onStop).buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(HTB.red) }
                } else { Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(failed ? .red : .green) }
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if !text.isEmpty {
                OutputBox(text: text, tint: failed ? .red : nil, fromEnd: live)
                    .background(.black.opacity(0.26))
            }
        }
        .glassCard(16).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ErrorCard: View {
    let text: String
    let cwd: String
    private var needsLogin: Bool { let t = text.lowercased(); return t.contains("/login") || t.contains("not logged in") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).textSelection(.enabled)
            if needsLogin {
                Button("Log in in Terminal") { TerminalApp.run("\(TerminalApp.claude) auth login", cwd: cwd) }.buttonStyle(HTBSecondary())
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .panel(RoundedRectangle(cornerRadius: 10), tint: HTB.amber.opacity(0.10), border: HTB.amber.opacity(0.5))
    }
}

struct ThinkingView: View {
    let text: String
    let live: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain").symbolEffect(.pulse, isActive: live && text.count < 2)
                    Text(live ? "Thinking…" : "Thought").font(.callout)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).rotationEffect(.degrees(open ? 90 : 0))
                }.foregroundStyle(.secondary)
            }.buttonStyle(.plain)
            if open {
                Text(text).font(.callout).italic().foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(.leading, 12).overlay(alignment: .leading) { Capsule().fill(.secondary.opacity(0.4)).frame(width: 2) }
            }
        }
    }
}

struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(.secondary).frame(width: 6, height: 6)
                    .opacity(reduceMotion || on ? 1 : 0.25)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }.onAppear { on = true }.accessibilityLabel("Claude is working")
    }
}
