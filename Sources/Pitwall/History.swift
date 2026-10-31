import Foundation
import AppKit

struct SessionMeta: Identifiable, Hashable {
    var id: String
    var path: String
    var cwd: String
    var title: String
    var date: Date
    var branch: String?
    var entrypoint: String?
    var searchText: String
}

/// Incrementally turns Claude Code's JSONL transcript lines into chat messages.
/// Used for the initial load and for live-tailing a session that is running in a terminal.
final class TranscriptParser {
    var messages: [ChatMessage] = []
    var contextTokens = 0
    var customTitle: String?
    var aiTitle: String?

    private var carry = Data()
    private var toolIndex: [String: (Int, Int)] = [:]
    private var byAPI: [String: Int] = [:]

    /// Feed raw bytes; a trailing partial line is kept until the next call.
    func consume(_ data: Data) {
        var chunk = carry + data
        carry = Data()
        if chunk.last != 0x0A, let nl = chunk.lastIndex(of: 0x0A) {
            carry = chunk.subdata(in: chunk.index(after: nl)..<chunk.endIndex)
            chunk = chunk.subdata(in: chunk.startIndex..<chunk.index(after: nl))
        } else if chunk.last != 0x0A {
            carry = chunk; return
        }
        for line in chunk.split(separator: 0x0A) where line.count < 6_000_000 { parse(Data(line)) }
    }

    private static let skipPrefixes = ["<system-reminder", "<command-", "<local-command", "Caveat:", "[Request interrupted"]

    static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        for p in skipPrefixes where t.hasPrefix(p) { return nil }
        return t
    }

    private func parse(_ line: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        switch o["type"] as? String {
        case "custom-title": customTitle = o["customTitle"] as? String
        case "ai-title": aiTitle = o["aiTitle"] as? String
        case "user":
            guard o["isSidechain"] as? Bool != true, o["isMeta"] as? Bool != true,
                  let msg = o["message"] as? [String: Any] else { return }
            var blocks: [Block] = []
            if let s = msg["content"] as? String {
                if let t = Self.clean(s) { blocks.append(Block(kind: .text, text: t)) }
            } else if let arr = msg["content"] as? [[String: Any]] {
                for c in arr {
                    switch c["type"] as? String {
                    case "text":
                        if let t = (c["text"] as? String).flatMap(Self.clean) { blocks.append(Block(kind: .text, text: t)) }
                    case "image":
                        if let src = c["source"] as? [String: Any], let b64 = src["data"] as? String,
                           let d = Data(base64Encoded: b64) { blocks.append(Block(kind: .image, imageData: d)) }
                    case "tool_result": attachResult(c)
                    default: break
                    }
                }
            }
            if !blocks.isEmpty {
                messages.append(ChatMessage(role: .user, blocks: blocks, date: Self.date(o["timestamp"])))
            }
        case "assistant":
            guard o["isSidechain"] as? Bool != true, let msg = o["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return }
            let apiID = msg["id"] as? String ?? UUID().uuidString
            if let u = msg["usage"] as? [String: Any] {
                let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (u[$1] as? Int ?? 0) }
                if n > 0 { contextTokens = n }
            }
            // One record per content block share a message id: merge them into one message.
            let mi: Int
            if let i = byAPI[apiID] { mi = i } else {
                messages.append(ChatMessage(role: .assistant, apiID: apiID, date: Self.date(o["timestamp"])))
                mi = messages.count - 1; byAPI[apiID] = mi
            }
            for c in content {
                switch c["type"] as? String {
                case "text":
                    if let t = c["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages[mi].blocks.append(Block(kind: .text, text: t))
                    }
                case "thinking":
                    if let t = c["thinking"] as? String, !t.isEmpty { messages[mi].blocks.append(Block(kind: .thinking, text: t)) }
                case "tool_use":
                    var b = Block(kind: .tool)
                    b.toolID = c["id"] as? String ?? ""; b.toolName = c["name"] as? String ?? ""
                    if let input = c["input"], let d = try? JSONSerialization.data(withJSONObject: input) {
                        b.inputJSON = String(decoding: d, as: UTF8.self)
                    }
                    messages[mi].blocks.append(b)
                    toolIndex[b.toolID] = (mi, messages[mi].blocks.count - 1)
                default: break
                }
            }
        case "system":
            if o["subtype"] as? String == "compact_boundary" {
                messages.append(ChatMessage(role: .assistant, blocks: [Block(kind: .notice, text: "Conversation compacted")]))
            }
        default: break
        }
    }

    private func attachResult(_ c: [String: Any]) {
        guard let tid = c["tool_use_id"] as? String, let (mi, bi) = toolIndex[tid], mi < messages.count,
              bi < messages[mi].blocks.count else { return }
        var out = ""
        if let s = c["content"] as? String { out = s }
        else if let parts = c["content"] as? [[String: Any]] { out = parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        messages[mi].blocks[bi].result = out
        messages[mi].blocks[bi].isError = c["is_error"] as? Bool ?? false
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static func date(_ v: Any?) -> Date { (v as? String).flatMap(iso.date) ?? Date() }
}

/// Reads Claude Code's own on-disk history (~/.claude), so terminal sessions show up here and vice versa.
enum History {
    nonisolated(unsafe) static var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    nonisolated(unsafe) static var historyFile: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")

    // MARK: Index (cheap: head + tail of each file only)

    nonisolated(unsafe) private static var metaCache: [String: (date: Date, meta: SessionMeta?)] = [:]
    nonisolated(unsafe) private static var promptCache: (path: String, stamp: Date, entries: [PromptEntry])?
    private static let cacheLock = NSLock()

    static func scan() -> [SessionMeta] { scanAll().metas }

    /// One pass for the whole app: the session index plus prompt history. The app calls this every few seconds,
    /// so a transcript is only re-read when its modification time changed, and history.jsonl is parsed once.
    static func scanAll() -> (metas: [SessionMeta], prompts: [PromptEntry]) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let entries = cachedPromptEntries()
        var bySession: [String: [String]] = [:]
        for e in entries { if let s = e.session { bySession[s, default: []].append(e.text) } }

        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return ([], entries) }
        var out: [SessionMeta] = []
        var seen: [String: (date: Date, meta: SessionMeta?)] = [:]
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                let id = f.deletingPathExtension().lastPathComponent
                let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let entry: (date: Date, meta: SessionMeta?)
                if let c = metaCache[f.path], c.date == date { entry = c } else { entry = (date, meta(file: f, id: id, date: date)) }
                seen[f.path] = entry
                guard var m = entry.meta else { continue }
                m.searchText = ([m.title] + (bySession[id] ?? [])).joined(separator: "\n").lowercased()
                out.append(m)
            }
        }
        metaCache = seen
        return (out, entries)
    }

    private static func cachedPromptEntries() -> [PromptEntry] {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: historyFile.path))?[.modificationDate] as? Date ?? .distantPast
        if let c = promptCache, c.path == historyFile.path, c.stamp == stamp { return c.entries }
        let e = promptEntries()
        promptCache = (historyFile.path, stamp, e)
        return e
    }

    private static func meta(file: URL, id: String, date: Date) -> SessionMeta? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0

        // The first record can be huge (a pasted image or file), so widen the window until we find it.
        var cwd: String?, branch: String?, entry: String?, firstPrompt: String?
        var headCustom: String?
        for limit in [96_000, 1_000_000, 8_000_000] {
            try? h.seek(toOffset: 0)
            let head = (try? h.read(upToCount: limit)) ?? Data()
            (cwd, branch, entry, firstPrompt, headCustom) = (nil, nil, nil, nil, nil)
            for line in head.split(separator: 0x0A) {
                guard let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if o["type"] as? String == "custom-title" { headCustom = o["customTitle"] as? String }
                guard o["type"] as? String == "user", o["isSidechain"] as? Bool != true,
                      let msg = o["message"] as? [String: Any] else { continue }
                if cwd == nil { cwd = o["cwd"] as? String; branch = o["gitBranch"] as? String; entry = o["entrypoint"] as? String }
                if firstPrompt == nil, let t = promptText(msg["content"]) { firstPrompt = t }
            }
            if (cwd != nil && firstPrompt != nil) || UInt64(head.count) >= size { break }
        }
        guard let cwd, let firstPrompt else { return nil }

        // Title precedence mirrors the terminal's /resume picker: /rename > AI title > first prompt.
        var custom: String?, ai: String?
        try? h.seek(toOffset: size > 160_000 ? size - 160_000 : 0)
        let tail = (try? h.readToEnd()) ?? Data()
        for line in tail.split(separator: 0x0A).reversed() where line.count < 2_000 {
            guard custom == nil || ai == nil,
                  let s = String(data: Data(line), encoding: .utf8), s.contains("-title\""),
                  let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if custom == nil, let t = o["customTitle"] as? String { custom = t }
            if ai == nil, let t = o["aiTitle"] as? String { ai = t }
        }
        let title = custom ?? headCustom ?? ai ?? String(firstPrompt.prefix(60))
        return SessionMeta(id: id, path: file.path, cwd: cwd, title: title, date: date,
                           branch: branch, entrypoint: entry, searchText: "")
    }

    private static func promptText(_ content: Any?) -> String? {
        if let s = content as? String { return TranscriptParser.clean(s) }
        if let arr = content as? [[String: Any]],
           let t = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String { return TranscriptParser.clean(t) }
        return nil
    }

    // MARK: Prompt history (~/.claude/history.jsonl)

    struct PromptEntry { var text: String; var project: String; var session: String?; var ts: Double }

    static func promptEntries() -> [PromptEntry] {
        guard let data = try? Data(contentsOf: historyFile) else { return [] }
        return data.split(separator: 0x0A).compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let d = o["display"] as? String, !d.isEmpty else { return nil }
            return PromptEntry(text: d, project: o["project"] as? String ?? "",
                               session: o["sessionId"] as? String, ts: o["timestamp"] as? Double ?? 0)
        }
    }

    // MARK: Full transcript

    /// Parses the whole file; returns the parser (to keep tailing) and the byte offset it consumed.
    static func load(path: String) -> (parser: TranscriptParser, offset: UInt64) {
        let p = TranscriptParser()
        let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        p.consume(data)
        return (p, UInt64(data.count))
    }

    static func read(path: String, from offset: UInt64) -> (Data, UInt64) {
        guard let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return (Data(), offset) }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? offset
        guard end > offset else { return (Data(), end) }
        try? h.seek(toOffset: offset)
        return ((try? h.readToEnd()) ?? Data(), end)
    }
}
