import SwiftUI

extension Block {
    var toolIcon: (name: String, color: Color) {
        switch toolName {
        case "Bash": ("terminal", .orange)
        case "Read": ("doc.text", .blue)
        case "Write": ("square.and.pencil", .purple)
        case "Edit", "MultiEdit", "NotebookEdit": ("pencil.line", .purple)
        case "Grep": ("magnifyingglass", .teal)
        case "Glob": ("doc.text.magnifyingglass", .teal)
        case "WebFetch", "WebSearch": ("globe", .cyan)
        case "Task", "Agent": ("person.2", .pink)
        case "TodoWrite": ("checklist", .green)
        case "AskUserQuestion": ("questionmark.bubble", .yellow)
        case "ExitPlanMode", "EnterPlanMode": ("map", .mint)
        case "Skill": ("sparkles", .pink)
        case "Monitor": ("waveform.path.ecg", .teal)
        default: ("wrench.and.screwdriver", .gray)
        }
    }

    var toolSummary: String {
        let i = input
        func s(_ k: String) -> String? { i[k] as? String }
        let short: (String) -> String = { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        switch toolName {
        case "Bash": return s("description") ?? s("command") ?? ""
        case "Read", "Write", "Edit", "MultiEdit": return short(s("file_path") ?? "")
        case "NotebookEdit": return short(s("notebook_path") ?? "")
        case "Grep", "Glob": return s("pattern") ?? ""
        case "WebFetch": return s("url") ?? ""
        case "WebSearch": return s("query") ?? ""
        case "Task", "Agent": return s("description") ?? ""
        case "TodoWrite": return "\((i["todos"] as? [[String: Any]])?.count ?? 0) items"
        case "AskUserQuestion": return ((i["questions"] as? [[String: Any]])?.first?["question"] as? String) ?? ""
        case "ExitPlanMode": return "Plan"
        case "Skill": return s("skill") ?? s("name") ?? ""
        default: return toolName.hasPrefix("mcp__") ? toolName.replacingOccurrences(of: "mcp__", with: "") : ""
        }
    }
}

struct ToolCard: View {
    let block: Block
    let live: Bool
    @State private var open: Bool

    init(block: Block, live: Bool) {
        self.block = block; self.live = live
        _open = State(initialValue: ["Edit", "MultiEdit", "Write", "TodoWrite", "ExitPlanMode"].contains(block.toolName))
    }

    private var running: Bool { block.result == nil && live }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy(duration: 0.22)) { open.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: block.toolIcon.name).foregroundStyle(block.toolIcon.color).frame(width: 18)
                    Text(block.toolName.hasPrefix("mcp__") ? "MCP" : block.toolName).fontWeight(.semibold)
                    Text(block.toolSummary).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    status
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain)

            if open { detail.transition(.opacity) }
        }
        .glassCard(16)
    }

    @ViewBuilder private var status: some View {
        if running { ProgressView().controlSize(.small) }
        else if block.isError { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
        else if block.result != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
    }

    @ViewBuilder private var detail: some View {
        let i = block.input
        VStack(alignment: .leading, spacing: 0) {
            switch block.toolName {
            case "Edit":
                DiffView(old: i["old_string"] as? String ?? "", new: i["new_string"] as? String ?? "")
            case "MultiEdit":
                ForEach(Array((i["edits"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, e in
                    DiffView(old: e["old_string"] as? String ?? "", new: e["new_string"] as? String ?? "")
                }
            case "Write":
                DiffView(old: "", new: i["content"] as? String ?? "")
            case "Bash":
                OutputBox(text: "$ " + (i["command"] as? String ?? ""), tint: .orange)
                if let r = block.result, !r.isEmpty { OutputBox(text: r, tint: block.isError ? .red : nil) }
            case "TodoWrite":
                TodoList(todos: i["todos"] as? [[String: Any]] ?? [])
            case "ExitPlanMode":
                MarkdownView(text: i["plan"] as? String ?? "").padding(14)
            case "AskUserQuestion":
                if let r = block.result { OutputBox(text: r, tint: nil) }
            default:
                OutputBox(text: pretty(block.inputJSON), tint: nil)
                if let r = block.result, !r.isEmpty { OutputBox(text: r, tint: block.isError ? .red : nil) }
            }
        }
        .background(.black.opacity(0.26))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
    }

    private func pretty(_ json: String) -> String {
        guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d),
              let p = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return json }
        return String(decoding: p, as: UTF8.self)
    }
}

struct OutputBox: View {
    let text: String
    let tint: Color?
    /// Show the last lines instead of the first (a command that is still producing output).
    var fromEnd = false
    private static let maxLines = 30

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let shown = (fromEnd ? lines.suffix(Self.maxLines) : lines.prefix(Self.maxLines)).joined(separator: "\n")
        VStack(alignment: .leading, spacing: 4) {
            if fromEnd, lines.count > Self.maxLines {
                Text("… \(lines.count - Self.maxLines) earlier lines").font(.caption).foregroundStyle(.tertiary)
            }
            Text(shown).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(tint ?? .secondary).textSelection(.enabled)
            if !fromEnd, lines.count > Self.maxLines {
                Text("… \(lines.count - Self.maxLines) more lines").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiffView: View {
    let old: String, new: String
    private static let cap = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rows(old, "−", .red)
            rows(new, "+", .green)
        }.padding(.vertical, 6)
    }

    @ViewBuilder private func rows(_ s: String, _ sign: String, _ color: Color) -> some View {
        if !s.isEmpty {
            let lines = s.components(separatedBy: "\n")
            ForEach(Array(lines.prefix(Self.cap).enumerated()), id: \.offset) { _, l in
                HStack(alignment: .top, spacing: 8) {
                    Text(sign).foregroundStyle(color)
                    Text(l.isEmpty ? " " : l).foregroundStyle(color.opacity(0.95))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 14).background(color.opacity(0.13))
            }
            if lines.count > Self.cap {
                Text("… \(lines.count - Self.cap) more lines").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14).padding(.vertical, 2)
            }
        }
    }
}

struct TodoList: View {
    let todos: [[String: Any]]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(todos.enumerated()), id: \.offset) { _, t in
                let status = t["status"] as? String ?? "pending"
                HStack(spacing: 10) {
                    Image(systemName: status == "completed" ? "checkmark.circle.fill"
                          : status == "in_progress" ? "circle.dotted.circle" : "circle")
                        .foregroundStyle(status == "completed" ? .green : status == "in_progress" ? .blue : .secondary)
                    Text(t["content"] as? String ?? "")
                        .strikethrough(status == "completed")
                        .foregroundStyle(status == "completed" ? .secondary : .primary)
                    Spacer(minLength: 0)
                }.font(.callout)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
