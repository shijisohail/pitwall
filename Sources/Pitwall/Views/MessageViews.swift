import SwiftUI
import AppKit

struct MessageView: View {
    let message: ChatMessage
    let live: Bool
    let cwd: String

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(message.blocks) { b in
                    if b.kind == .image, let d = b.imageData, let img = NSImage(data: d) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else if b.kind == .text {
                        Text(b.text).textSelection(.enabled).lineSpacing(3)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .panel(RoundedRectangle(cornerRadius: 10), tint: HTB.green.opacity(0.09), border: HTB.green.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 80)
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(message.blocks) { b in
                    switch b.kind {
                    case .text: MarkdownView(text: b.text)
                    case .thinking: ThinkingView(text: b.text, live: live)
                    case .tool: ToolCard(block: b, live: live)
                    case .notice: NoticeLine(text: b.text)
                    case .output: OutputCard(title: b.toolName, text: b.text)
                    case .local: LocalCard(command: b.toolName, text: b.text, failed: b.isError)
                    case .image: EmptyView()
                    case .error: ErrorCard(text: b.text, cwd: cwd)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right.2").foregroundStyle(.orange)
                Text(command).font(.system(size: 12.5, design: .monospaced)).lineLimit(2)
                Spacer()
                if text.isEmpty { ProgressView().controlSize(.small) }
                else { Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(failed ? .red : .green) }
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if !text.isEmpty {
                OutputBox(text: text, tint: failed ? .red : nil)
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
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(.secondary).frame(width: 6, height: 6)
                    .opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }.onAppear { on = true }
    }
}
