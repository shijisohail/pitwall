import Foundation

/// Claude Code reports a finished background agent by injecting a `<task-notification>` block as a user-role message.
/// It is bookkeeping for the model, not something the user typed, so the UI shows it as a compact status line.
struct TaskNotification: Identifiable, Equatable {
    var id: String { taskID + String(raw.hashValue) }
    var taskID = ""
    var status = ""
    var summary = ""
    var outputFile: String?
    var durationMS: Int?
    var toolUses: Int?
    var tokens: Int?
    var raw = ""

    private static let open = "<task-notification>", close = "</task-notification>"

    /// Pulls every notification out of `text`; whatever else the message said comes back as `rest`.
    static func split(_ text: String) -> (notes: [TaskNotification], rest: String) {
        guard text.contains(open) else { return ([], text) }
        var notes: [TaskNotification] = [], rest = "", cursor = text.startIndex
        while let o = text.range(of: open, range: cursor..<text.endIndex) {
            guard let c = text.range(of: close, range: o.upperBound..<text.endIndex) else { break }
            rest += text[cursor..<o.lowerBound]
            notes.append(parse(String(text[o.upperBound..<c.lowerBound]), raw: String(text[o.lowerBound..<c.upperBound])))
            cursor = c.upperBound
        }
        rest += text[cursor...]
        return (notes, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parse(_ body: String, raw: String) -> TaskNotification {
        func tag(_ name: String) -> String? {
            guard let a = body.range(of: "<\(name)>"), let b = body.range(of: "</\(name)>", range: a.upperBound..<body.endIndex) else { return nil }
            let v = body[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }
        return TaskNotification(taskID: tag("task-id") ?? "", status: tag("status") ?? "", summary: tag("summary") ?? "",
                                outputFile: tag("output-file"), durationMS: tag("duration_ms").flatMap(Int.init),
                                toolUses: tag("tool_uses").flatMap(Int.init), tokens: tag("subagent_tokens").flatMap(Int.init), raw: raw)
    }

    var title: String { summary.isEmpty ? "Background agent \(status.isEmpty ? "update" : status)" : summary }

    /// "53s · 5 tools · 27.7k tokens"
    var detail: String {
        var p: [String] = []
        if let ms = durationMS { let s = ms / 1000; p.append(s < 60 ? "\(max(s, 1))s" : "\(s / 60)m \(s % 60)s") }
        if let t = toolUses { p.append("\(t) tool\(t == 1 ? "" : "s")") }
        if let k = tokens { p.append(k >= 1000 ? String(format: "%.1fk tokens", Double(k) / 1000) : "\(k) tokens") }
        return p.joined(separator: " · ")
    }
}
