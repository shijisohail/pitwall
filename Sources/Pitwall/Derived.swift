import Foundation

struct FileChange: Identifiable {
    var path: String
    var hunks: [(old: String, new: String)] = []
    var added = 0
    var removed = 0
    var isNew = false
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var dir: String { (path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

struct FeedLine: Identifiable {
    enum State { case done, running, failed, text }
    var id: String
    var state: State
    var title: String
    var detail: String
}

private func lines(_ s: String) -> Int { s.isEmpty ? 0 : s.components(separatedBy: "\n").count }

extension Conversation {
    /// Files this session actually changed, rebuilt from the applied Edit / MultiEdit / Write tool calls.
    func fileChanges() -> [FileChange] {
        var map: [String: FileChange] = [:]
        var order: [String] = []
        func add(_ path: String, old: String, new: String, isNew: Bool = false) {
            guard !path.isEmpty else { return }
            if map[path] == nil { map[path] = FileChange(path: path, isNew: isNew); order.append(path) }
            map[path]!.hunks.append((old, new))
            map[path]!.added += lines(new); map[path]!.removed += lines(old)
        }
        for m in messages {
            for b in m.blocks where b.kind == .tool && b.result != nil && !b.isError {
                let i = b.input
                switch b.toolName {
                case "Edit": add(i["file_path"] as? String ?? "", old: i["old_string"] as? String ?? "", new: i["new_string"] as? String ?? "")
                case "MultiEdit":
                    for e in i["edits"] as? [[String: Any]] ?? [] {
                        add(i["file_path"] as? String ?? "", old: e["old_string"] as? String ?? "", new: e["new_string"] as? String ?? "")
                    }
                case "Write": add(i["file_path"] as? String ?? "", old: "", new: i["content"] as? String ?? "", isNew: true)
                default: break
                }
            }
        }
        return order.compactMap { map[$0] }
    }

    /// Cheap per-render summary for Pit Wall cards.
    var diffStat: (files: Int, added: Int, removed: Int) {
        guard !messages.isEmpty else { return (0, 0, 0) }
        let c = fileChanges()
        return (c.count, c.reduce(0) { $0 + $1.added }, c.reduce(0) { $0 + $1.removed })
    }

    /// The last few steps of the latest assistant turn, for a live mini-feed.
    var feed: [FeedLine] {
        guard let m = messages.last(where: { $0.role == .assistant && !$0.blocks.isEmpty }) else { return [] }
        let tools = m.blocks.filter { $0.kind == .tool }.suffix(3)
        if !tools.isEmpty {
            return tools.map { b in
                FeedLine(id: b.id, state: b.result == nil ? (isRunning ? .running : .done) : (b.isError ? .failed : .done),
                         title: b.toolName, detail: b.toolSummary)
            }
        }
        if let t = m.blocks.last(where: { $0.kind == .text })?.text {
            return [FeedLine(id: m.id, state: .text, title: "", detail: String(t.prefix(140)))]
        }
        if isRunning { return [FeedLine(id: m.id, state: .running, title: "Thinking", detail: "")] }
        return []
    }

    func latestTool(_ name: String) -> Block? {
        for m in messages.suffix(160).reversed() {
            if let b = m.blocks.last(where: { $0.kind == .tool && $0.toolName == name }) { return b }
        }
        return nil
    }

    var latestTodos: [[String: Any]] { latestTool("TodoWrite")?.input["todos"] as? [[String: Any]] ?? [] }

    var todoProgress: (done: Int, total: Int)? {
        let t = latestTodos
        return t.isEmpty ? nil : (t.filter { $0["status"] as? String == "completed" }.count, t.count)
    }

    var latestPlan: String? { latestTool("ExitPlanMode")?.input["plan"] as? String }
}
