import Foundation
import AppKit
import Observation

@MainActor @Observable
final class Conversation: Identifiable {
    enum LoadState { case loaded, notLoaded, loading }

    let id: String
    var cwd: String
    var branch: String?
    var historyPath: String?
    var loadState: LoadState = .loaded
    var searchText = ""
    var entrypoint: String?
    var title: String
    var messages: [ChatMessage] = []
    var sessionID: String?
    var model = "default" { didSet { if model != oldValue { applyModel() } } }
    var effort: String?
    var permission: PermissionMode = .acceptEdits { didSet { if permission != oldValue { applyPermission(oldValue) } } }
    var additionalDirs: [String] = []
    var modelName: String?
    var cost = 0.0
    var contextTokens = 0
    var contextWindow = 200_000
    var updatedAt: Date
    var isRunning = false
    var approvals: [Approval] = []
    var externallyActive = false
    var retryNote: String?
    var turnStart: Date?

    @ObservationIgnored var runner: ClaudeRunner?
    @ObservationIgnored var blockMap: [Int: Int] = [:]
    @ObservationIgnored weak var store: Store?
    @ObservationIgnored var parser: TranscriptParser?
    @ObservationIgnored var tailOffset: UInt64 = 0
    @ObservationIgnored var tailTimer: Timer?
    @ObservationIgnored var forkFrom: String?
    @ObservationIgnored var needsRestart = false
    @ObservationIgnored var stopRequested = false
    @ObservationIgnored var turnHadAssistant = false
    @ObservationIgnored var lastPrompt = ""
    @ObservationIgnored var queuedLocal: [String] = []
    @ObservationIgnored var turnID = 0

    static let placeholderTitle = "New session"

    init(cwd: String) {
        id = UUID().uuidString
        self.cwd = cwd; title = Self.placeholderTitle; updatedAt = Date()
        permission = AppSettings.shared.defaultPermission
    }

    /// A past Claude Code session: metadata now, transcript loaded on demand.
    init(meta m: SessionMeta) {
        id = m.id; cwd = m.cwd; branch = m.branch; historyPath = m.path; entrypoint = m.entrypoint
        title = m.title; sessionID = m.id; updatedAt = m.date
        loadState = .notLoaded; searchText = m.searchText
        permission = AppSettings.shared.defaultPermission
    }

    func update(from m: SessionMeta) {
        title = m.title; searchText = m.searchText; entrypoint = m.entrypoint
        if historyPath == nil { historyPath = m.path; attachTail() }
        if runner == nil { updatedAt = m.date }
        externallyActive = runner == nil && Date().timeIntervalSince(m.date) < 12
    }

    // MARK: History + live tail (terminal ⇄ Pitwall)

    func loadHistoryIfNeeded() {
        guard let p = historyPath, loadState == .notLoaded else { return }
        loadState = .loading
        Task { [weak self] in
            let r = await Task.detached(priority: .userInitiated) { History.load(path: p) }.value
            guard let self else { return }
            self.parser = r.parser; self.tailOffset = r.offset
            self.messages = r.parser.messages
            if self.contextTokens == 0 { self.contextTokens = r.parser.contextTokens }
            self.loadState = .loaded
            self.startTail()
        }
    }

    /// Session created in Pitwall whose transcript file now exists: start tracking it from its end.
    private func attachTail() {
        guard let p = historyPath, parser == nil else { return }
        let np = TranscriptParser(); np.messages = messages
        parser = np; tailOffset = History.read(path: p, from: UInt64.max).1
    }

    func startTail() {
        guard historyPath != nil, tailTimer == nil else { return }
        tailTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollTail() }
        }
    }

    func stopTail() { tailTimer?.invalidate(); tailTimer = nil }

    private func pollTail() {
        guard let p = historyPath, runner == nil, loadState == .loaded, let parser else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: p)
        if let m = attrs?[.modificationDate] as? Date { externallyActive = Date().timeIntervalSince(m) < 12 }
        let (data, end) = History.read(path: p, from: tailOffset)
        guard !data.isEmpty else { return }
        parser.consume(data); tailOffset = end
        messages = parser.messages
        if let t = parser.customTitle { title = t }
        contextTokens = parser.contextTokens > 0 ? parser.contextTokens : contextTokens
        updatedAt = Date()
    }

    /// After our own process ran, our in-memory messages are the truth; skip what it wrote to disk.
    private func resyncTail() {
        guard let p = historyPath, let old = parser else { return }
        let fresh = TranscriptParser()      // its tool/message indices must describe `messages`, not the old layout
        fresh.messages = messages; fresh.customTitle = old.customTitle; fresh.aiTitle = old.aiTitle
        parser = fresh
        tailOffset = History.read(path: p, from: UInt64.max).1
    }

    // MARK: Sending

    @discardableResult
    func send(_ raw: String, images: [NSImage] = []) -> Bool {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(text.isEmpty && images.isEmpty), !isRunning, loadState != .loading else { return false }
        if images.isEmpty, text.hasPrefix("/") {
            switch routeSlash(text) {
            case .handled: return true
            case .forward(let t): text = t
            }
        }
        if images.isEmpty, text.hasPrefix("!"), text.count > 1 { runLocal(String(text.dropFirst())); return true }
        if externallyActive, runner == nil {
            switch confirmExternal() {
            case .cancel: return false
            case .fork: store?.fork(self)?.send(raw, images: images); return true
            case .anyway: break
            }
        }

        var blocks: [Block] = images.compactMap { Self.png($0) }.map { Block(kind: .image, imageData: $0) }
        if !text.isEmpty { blocks.append(Block(kind: .text, text: text)) }
        messages.append(ChatMessage(role: .user, blocks: blocks))
        if title == Self.placeholderTitle, !text.isEmpty { title = String(text.prefix(48)) }
        lastPrompt = text; updatedAt = Date()
        turnHadAssistant = false; stopRequested = false

        do {
            if needsRestart { runner?.stop(); runner = nil; needsRestart = false }
            if runner?.isAlive != true { try startRunner() }
            isRunning = true; turnStart = Date(); turnID += 1
            var body = text
            if !queuedLocal.isEmpty, !text.hasPrefix("/") {
                body = "For context, I ran these shell commands locally:\n```\n" + queuedLocal.joined(separator: "\n\n") + "\n```\n\n" + text
                queuedLocal = []
            }
            if images.isEmpty { runner?.sendUser(body) }
            else {
                var content: [[String: Any]] = images.compactMap { Self.png($0) }.map {
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": $0.base64EncodedString()]]
                }
                content.append(["type": "text", "text": body])
                runner?.sendUser(content)
            }
        } catch { fail(error.localizedDescription) }
        return true
    }

    func stop() {
        stopRequested = true
        approvals.removeAll()
        runner?.interrupt()
        // If the CLI doesn't honour the interrupt quickly, kill it; the session resumes on the next send.
        // Tied to this turn: a prompt sent after a successful stop must not be killed by this timer.
        let turn = turnID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.isRunning, self.turnID == turn else { return }
            self.runner?.stop(); self.runner = nil
            self.isRunning = false
            self.messages.append(ChatMessage(role: .assistant, blocks: [Block(kind: .notice, text: "Stopped")]))
        }
    }

    private func startRunner() throws {
        let r = ClaudeRunner()
        r.onEvent = { [weak self] e in self?.handle(e) }
        r.onExit = { [weak self] code, err in
            guard let self else { return }
            let was = self.isRunning
            self.runner = nil; self.isRunning = false; self.turnStart = nil; self.approvals.removeAll()
            self.resyncTail()
            if was { self.fail(code == 0 ? "Claude exited unexpectedly." : "Claude exited (\(code)). \(err)") }
        }
        var o = ClaudeRunner.Options(cwd: cwd)
        o.model = model == "default" ? nil : model
        o.permission = permission; o.effort = effort
        o.resume = forkFrom ?? sessionID; o.fork = forkFrom != nil; o.addDirs = additionalDirs
        if permission == .bypassPermissions { o.extraArgs = ["--allow-dangerously-skip-permissions"] }
        try r.start(o)
        runner = r; forkFrom = nil
        stopTail()
        let dir = cwd
        r.request("initialize") { [weak self] body in
            if let b = body { self?.store?.catalogs[dir] = Catalog(b) }
        }
    }

    func teardown() { runner?.stop(); runner = nil; stopTail(); isRunning = false }

    func fail(_ msg: String) {
        messages.append(ChatMessage(role: .assistant, blocks: [Block(kind: .error, text: msg)]))
        isRunning = false; turnStart = nil
    }

    func note(_ text: String) {
        messages.append(ChatMessage(role: .assistant, blocks: [Block(kind: .notice, text: text)]))
    }

    func card(_ title: String, _ body: String) {
        messages.append(ChatMessage(role: .assistant, blocks: [Block(kind: .output, text: body, toolName: title)]))
    }

    // MARK: Live settings (no restart needed for model / permission mode)

    private func applyModel() {
        guard let r = runner, r.isAlive else { return }
        r.request("set_model", ["model": model]) { [weak self] body in
            guard let self else { return }
            if let m = body?["model"] as? String { self.modelName = m } else { self.note("Couldn't switch to \(self.model).") }
        }
    }

    private func applyPermission(_ old: PermissionMode) {
        guard let r = runner, r.isAlive else { return }
        if old == .bypassPermissions {
            // The live process is still in bypass mode and can't be lowered in place: end it now rather than let it run unchecked.
            r.stop(); runner = nil; needsRestart = false; resyncTail()
            if isRunning { isRunning = false; turnStart = nil; approvals.removeAll(); note("Stopped: Full access was turned off") }
            return
        }
        if permission == .bypassPermissions { needsRestart = true; return }
        r.request("set_permission_mode", ["mode": permission.control])
    }

    func setEffort(_ level: String?) {
        effort = level
        if runner?.isAlive == true { needsRestart = true }
    }

    // MARK: Approvals

    func allow(_ a: Approval, input: [String: Any]? = nil, remember: [String: Any]? = nil) {
        var resp: [String: Any] = ["behavior": "allow", "updatedInput": input ?? a.input]
        if let remember {
            resp["updatedPermissions"] = [remember]
            if remember["type"] as? String == "setMode", let m = remember["mode"] as? String,
               let pm = PermissionMode.allCases.first(where: { $0.control == m }) { setPermissionSilently(pm) }
        }
        runner?.respond(a.id, resp)
        approvals.removeAll { $0.id == a.id }
    }

    func deny(_ a: Approval, message: String? = nil) {
        runner?.respond(a.id, ["behavior": "deny", "message": (message?.isEmpty == false ? message! : "The user denied this action.")])
        approvals.removeAll { $0.id == a.id }
    }

    /// The CLI already switched modes itself; mirror it in the UI without re-sending a request.
    func setPermissionSilently(_ m: PermissionMode) {
        let r = runner; runner = nil; permission = m; runner = r
    }

    private func handleControlRequest(_ e: [String: Any]) {
        guard let id = e["request_id"] as? String, let r = e["request"] as? [String: Any] else { return }
        guard r["subtype"] as? String == "can_use_tool" else {
            Log.cli.warning("unsupported control request: \(r["subtype"] as? String ?? "?", privacy: .public)")
            runner?.respondError(id, "Pitwall doesn't handle \(r["subtype"] as? String ?? "this") requests yet."); return
        }
        let tool = r["tool_name"] as? String ?? ""
        approvals.append(Approval(
            id: id, kind: tool == "AskUserQuestion" ? .question : tool == "ExitPlanMode" ? .plan : .tool,
            tool: tool, input: r["input"] as? [String: Any] ?? [:],
            detail: r["description"] as? String, reason: r["decision_reason"] as? String,
            suggestions: r["permission_suggestions"] as? [[String: Any]] ?? []))
    }

    // MARK: Event handling (stream-json)

    func handle(_ e: [String: Any]) {
        let parent = e["parent_tool_use_id"]
        let isSub = parent != nil && !(parent is NSNull)
        switch e["type"] as? String {
        case "system": handleSystem(e)
        case "stream_event":
            if !isSub, let ev = e["event"] as? [String: Any] { handleStream(ev) }
        case "assistant":
            if !isSub, let m = e["message"] as? [String: Any] { handleAssistant(m) }
        case "user":
            if let m = e["message"] as? [String: Any] { handleToolResults(m) }
        case "control_request": handleControlRequest(e)
        case "control_cancel_request":
            if let id = e["request_id"] as? String { approvals.removeAll { $0.id == id } }
        case "rate_limit_event": store?.updateUsage(e)
        case "result": handleResult(e)
        default: break
        }
    }

    private func handleSystem(_ e: [String: Any]) {
        switch e["subtype"] as? String {
        case "init":
            if let sid = e["session_id"] as? String {
                sessionID = sid
                if historyPath == nil { store?.markOwned(sid) }
            }
            if let m = e["model"] as? String { modelName = m }
        case "session_title_changed":
            if let t = e["title"] as? String { title = t }
        case "compact_boundary":
            let pre = (e["compact_metadata"] as? [String: Any])?["pre_tokens"] as? Int
            note(pre.map { "Conversation compacted (was \($0 / 1000)k tokens)" } ?? "Conversation compacted")
        case "api_retry":
            let n = e["attempt"] as? Int ?? 1
            retryNote = "Retrying… (attempt \(n))"
        default: break
        }
    }

    private func handleResult(_ e: [String: Any]) {
        if let c = e["total_cost_usd"] as? Double { cost = c }      // whole-conversation total, also when resumed
        if let sid = e["session_id"] as? String { sessionID = sid }
        if let mu = e["modelUsage"] as? [String: Any],
           let w = mu.values.compactMap({ ($0 as? [String: Any])?["contextWindow"] as? Int }).max(), w > 0 { contextWindow = w }
        let sub = e["subtype"] as? String ?? ""
        let text = e["result"] as? String ?? ""
        if sub == "error_during_execution", stopRequested { note("Stopped") }
        else if e["is_error"] as? Bool == true || (sub != "success" && !sub.isEmpty) {
            fail(text.isEmpty ? "The run ended with an error (\(sub))." : text)
        } else if !turnHadAssistant, !text.isEmpty {
            card(lastPrompt, Limits.clip(text))       // a slash command's own output, e.g. /context or /usage
        }
        isRunning = false; turnStart = nil; approvals.removeAll(); retryNote = nil; stopRequested = false
        updatedAt = Date()
    }

    private func handleStream(_ ev: [String: Any]) {
        switch ev["type"] as? String {
        case "message_start":
            let m = ev["message"] as? [String: Any]
            turnHadAssistant = true; retryNote = nil
            messages.append(ChatMessage(role: .assistant, apiID: m?["id"] as? String))
            blockMap = [:]
            if let u = m?["usage"] as? [String: Any] {
                let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (u[$1] as? Int ?? 0) }
                if n > 0 { contextTokens = n }
            }
        case "content_block_start":
            guard let idx = ev["index"] as? Int, let cb = ev["content_block"] as? [String: Any], !messages.isEmpty else { return }
            var b: Block
            switch cb["type"] as? String {
            case "thinking": b = Block(kind: .thinking)
            case "tool_use":
                b = Block(kind: .tool)
                b.toolID = cb["id"] as? String ?? ""; b.toolName = cb["name"] as? String ?? ""
            default: b = Block(kind: .text)
            }
            messages[messages.count - 1].blocks.append(b)
            blockMap[idx] = messages[messages.count - 1].blocks.count - 1
        case "content_block_delta":
            guard let idx = ev["index"] as? Int, let bi = blockMap[idx], !messages.isEmpty,
                  let d = ev["delta"] as? [String: Any] else { return }
            let mi = messages.count - 1
            switch d["type"] as? String {
            case "text_delta": messages[mi].blocks[bi].text += d["text"] as? String ?? ""
            case "thinking_delta": messages[mi].blocks[bi].text += d["thinking"] as? String ?? ""
            case "input_json_delta": messages[mi].blocks[bi].inputJSON += d["partial_json"] as? String ?? ""
            default: break
            }
        default: break
        }
    }

    /// Final tool inputs arrive on the complete `assistant` event; replace the partial JSON we accumulated.
    private func handleAssistant(_ m: [String: Any]) {
        guard let content = m["content"] as? [[String: Any]] else { return }
        for c in content where c["type"] as? String == "tool_use" {
            guard let tid = c["id"] as? String, let input = c["input"],
                  let d = try? JSONSerialization.data(withJSONObject: input),
                  let s = String(data: d, encoding: .utf8) else { continue }
            if let (mi, bi) = find(tool: tid) { messages[mi].blocks[bi].inputJSON = s }
        }
    }

    private func handleToolResults(_ m: [String: Any]) {
        guard let content = m["content"] as? [[String: Any]] else { return }
        for c in content where c["type"] as? String == "tool_result" {
            guard let tid = c["tool_use_id"] as? String, let (mi, bi) = find(tool: tid) else { continue }
            var out = ""
            if let s = c["content"] as? String { out = s }
            else if let arr = c["content"] as? [[String: Any]] { out = arr.compactMap { $0["text"] as? String }.joined(separator: "\n") }
            messages[mi].blocks[bi].result = Limits.clip(out)
            messages[mi].blocks[bi].isError = c["is_error"] as? Bool ?? false
        }
    }

    private func find(tool id: String) -> (Int, Int)? {
        for mi in messages.indices.reversed() {
            if let bi = messages[mi].blocks.firstIndex(where: { $0.toolID == id }) { return (mi, bi) }
        }
        return nil
    }

    // MARK: Helpers

    static func png(_ img: NSImage, maxDim: CGFloat = 1600) -> Data? {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return nil }
        let k = min(1, maxDim / max(s.width, s.height))
        let w = Int(s.width * k), h = Int(s.height * k)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    enum ExternalChoice { case fork, anyway, cancel }

    private func confirmExternal() -> ExternalChoice {
        let a = NSAlert()
        a.messageText = "This session is active in a terminal"
        a.informativeText = "Two apps writing to one session can garble it. Fork it into a new session, or send anyway."
        a.addButton(withTitle: "Fork & Continue"); a.addButton(withTitle: "Send Anyway"); a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: return .fork
        case .alertSecondButtonReturn: return .anyway
        default: return .cancel
        }
    }
}
