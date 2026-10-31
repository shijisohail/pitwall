import SwiftUI
import AppKit

struct InspectorView: View {
    @Bindable var conversation: Conversation
    @Environment(Store.self) private var store
    @State private var tab = "changes"
    @State private var changes: [FileChange] = []
    @State private var collapsed: Set<String> = []
    @State private var reverted: Set<String> = []

    /// Changes only when a tool finishes or a message is added, not on every streamed token.
    private var token: Int {
        var n = 0
        for m in conversation.messages { for b in m.blocks where b.kind == .tool && b.result != nil { n += 1 } }
        return n &* 100_003 &+ conversation.messages.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                tabButton("changes", "Changes", badge: changes.count)
                tabButton("plan", "Plan")
                tabButton("context", "Context")
                tabButton("files", "Files")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case "plan": plan
                    case "context": context
                    case "files": files
                    default: changesTab
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
        }
        .padding(16).padding(.top, 14)
        .frame(width: 392).frame(maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.14))
        .task(id: token) { changes = conversation.fileChanges() }
    }

    private func tabButton(_ id: String, _ title: String, badge: Int = 0) -> some View {
        Button { tab = id } label: {
            HStack(spacing: 5) {
                Text(title)
                if badge > 0 { Text("\(badge)").font(.system(size: 10.5, weight: .bold)).padding(.horizontal, 5).background(.white.opacity(0.18), in: Capsule()) }
            }
            .font(.system(size: 12.5, weight: tab == id ? .semibold : .regular))
            .foregroundStyle(tab == id ? Color.primary : Color.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(tab == id ? Color.white.opacity(0.12) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Changes

    @ViewBuilder private var changesTab: some View {
        if changes.isEmpty {
            empty("No file changes yet", "Edits Claude makes in this session appear here as a live diff.")
        } else {
            HStack {
                Text("\(changes.count) file\(changes.count == 1 ? "" : "s") changed").fontWeight(.semibold)
                Spacer()
                Text("+\(changes.reduce(0) { $0 + $1.added })").foregroundStyle(.green)
                Text("−\(changes.reduce(0) { $0 + $1.removed })").foregroundStyle(.red)
            }.font(.system(size: 13, design: .monospaced))
            ForEach(changes) { f in fileCard(f) }
        }
    }

    private func fileCard(_ f: FileChange) -> some View {
        let open = !collapsed.contains(f.id)
        let isReverted = reverted.contains(f.id)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { withAnimation(.snappy(duration: 0.2)) { if open { collapsed.insert(f.id) } else { collapsed.remove(f.id) } } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name).font(.system(size: 12.5, weight: .medium, design: .monospaced)).lineLimit(1).strikethrough(isReverted)
                            Text(f.isNew && f.removed == 0 ? "new · " + f.dir : f.dir).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: 4)
                        Text("+\(f.added)").foregroundStyle(.green); Text("−\(f.removed)").foregroundStyle(.red)
                    }.font(.system(size: 12, design: .monospaced)).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { FilePolicy.openOrReveal(f.path) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Open file")
                Button { revert(f) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Revert with git checkout").disabled(isReverted)
            }.padding(.horizontal, 12).padding(.vertical, 9)
            if open && !isReverted {
                VStack(spacing: 0) {
                    ForEach(Array(f.hunks.enumerated()), id: \.offset) { i, h in
                        if i > 0 { Divider().opacity(0.3) }
                        DiffView(old: h.old, new: h.new)
                    }
                }.background(.black.opacity(0.28))
            }
        }
        .glassCard(14).clipShape(RoundedRectangle(cornerRadius: 14)).opacity(isReverted ? 0.5 : 1)
    }

    private func revert(_ f: FileChange) {
        let a = NSAlert()
        a.messageText = "Revert \(f.name)?"
        a.informativeText = "This runs `git checkout` on the file and discards ALL uncommitted changes to it, including edits that weren't made by Claude."
        a.addButton(withTitle: "Revert File"); a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Task {
            let (out, code) = await Shell.run("git checkout -- \(TerminalApp.quote(f.path))", cwd: conversation.cwd, timeout: 20)
            if code == 0 { reverted.insert(f.id); conversation.note("Reverted \(f.name)") }
            else { conversation.note("Couldn't revert \(f.name): \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))") }
        }
    }

    // MARK: Plan

    @ViewBuilder private var plan: some View {
        let todos = conversation.latestTodos
        if !todos.isEmpty {
            HStack {
                Text("Steps").fontWeight(.semibold)
                Spacer()
                if let p = conversation.todoProgress { Text("\(p.done)/\(p.total)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
            }
            TodoList(todos: todos).glassCard(14)
        }
        if let p = conversation.latestPlan {
            Text("Plan").fontWeight(.semibold)
            MarkdownView(text: p).padding(14).glassCard(14)
        }
        if todos.isEmpty && conversation.latestPlan == nil {
            empty("No plan yet", "Todo lists and plans Claude writes show up here. Try /plan to start in plan mode.")
        }
    }

    // MARK: Context

    private var context: some View {
        let c = conversation
        let pct = min(1, Double(c.contextTokens) / Double(max(c.contextWindow, 1)))
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Context window").fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(pct * 100))%").font(.system(size: 12.5, design: .monospaced))
                }
                Capsule().fill(.white.opacity(0.12)).frame(height: 7).overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(LinearGradient(colors: [HTB.green, pct > 0.8 ? HTB.red : HTB.cyan], startPoint: .leading, endPoint: .trailing)).frame(width: max(7, g.size.width * pct)) }
                }.frame(height: 7)
                Text("\(c.contextTokens / 1000)k of \(c.contextWindow / 1000)k tokens").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(14)

            VStack(alignment: .leading, spacing: 8) {
                row("Model", c.modelName ?? c.model)
                row("Effort", c.effort ?? "auto")
                row("Mode", c.permission.label)
                row("Cost", String(format: "$%.2f", c.cost))
                if let u = store.usage {
                    row("5-hour plan", "\(Int(u.fiveHour * 100))%")
                    row("7-day plan", "\(Int(u.sevenDay * 100))%")
                }
                if !c.additionalDirs.isEmpty { row("Extra folders", c.additionalDirs.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(14)

            HStack(spacing: 8) {
                Button("Show breakdown") { c.send("/context") }.buttonStyle(HTBSecondary())
                Button("Compact") { c.send("/compact") }.buttonStyle(HTBSecondary())
            }.disabled(c.isRunning).controlSize(.small)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).font(.system(size: 12.5, design: .monospaced)).lineLimit(1) }.font(.callout)
    }

    // MARK: Files

    @ViewBuilder private var files: some View {
        let touched = touchedFiles()
        if touched.isEmpty {
            empty("No files touched yet", "Files Claude reads, searches or edits are listed here.")
        } else {
            ForEach(touched, id: \.0) { path, ops in
                Button { FilePolicy.openOrReveal(path) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ops.contains("Edit") || ops.contains("Write") ? "pencil.line" : "doc.text")
                            .foregroundStyle(ops.contains("Edit") || ops.contains("Write") ? HTB.green : HTB.cyan).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(ops.sorted().joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).glassCard(12)
            }
        }
    }

    private func touchedFiles() -> [(String, Set<String>)] {
        var map: [String: Set<String>] = [:]
        var order: [String] = []
        for m in conversation.messages.suffix(600) {
            for b in m.blocks where b.kind == .tool {
                guard ["Read", "Edit", "MultiEdit", "Write", "NotebookEdit"].contains(b.toolName) else { continue }
                let i = b.input
                guard let p = (i["file_path"] as? String) ?? (i["notebook_path"] as? String) else { continue }
                if map[p] == nil { order.append(p) }
                map[p, default: []].insert(b.toolName == "MultiEdit" ? "Edit" : b.toolName)
            }
        }
        return order.reversed().prefix(60).map { ($0, map[$0] ?? []) }
    }

    private func empty(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).fontWeight(.medium)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 12)
    }
}
