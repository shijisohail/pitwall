import Foundation

/// Owns one long-lived `claude -p --input-format stream-json` process and speaks its control protocol.
final class ClaudeRunner {
    struct Options {
        var cwd: String
        var model: String? = nil
        var permission: PermissionMode = .acceptEdits
        var effort: String? = nil
        var resume: String? = nil
        var fork = false
        var addDirs: [String] = []
        var extraArgs: [String] = []
    }

    var onEvent: (([String: Any]) -> Void)?
    var onExit: ((Int32, String) -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var stderrText = ""
    private var pending: [String: ([String: Any]?) -> Void] = [:]   // main thread only

    var isAlive: Bool { process?.isRunning ?? false }

    static let claudePath: String? = {
        let home = NSHomeDirectory()
        for p in ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        sh.arguments = ["-l", "-c", "command -v claude"]
        let out = Pipe(); sh.standardOutput = out; sh.standardError = Pipe()
        try? sh.run(); sh.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }()

    func start(_ o: Options) throws {
        guard let path = Self.claudePath else {
            throw NSError(domain: "Pitwall", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Couldn't find the `claude` CLI. Install Claude Code and make sure it's on your PATH."])
        }
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--include-partial-messages", "--verbose",
                    "--permission-prompt-tool", "stdio",       // approvals + questions come to us as control requests
                    "--permission-mode", o.permission.flag]
        if let m = o.model { args += ["--model", m] }
        if let e = o.effort { args += ["--effort", e] }
        if let r = o.resume { args += ["--resume", r]; if o.fork { args.append("--fork-session") } }
        for d in o.addDirs { args += ["--add-dir", d] }
        args += o.extraArgs

        let p = Process()
        // Login shell so the CLI sees the user's real PATH (node etc.) even when launched from Finder.
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "exec \"$0\" \"$@\"", path] + args
        p.currentDirectoryURL = URL(fileURLWithPath: o.cwd)

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        stdin = inPipe.fileHandleForWriting

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.ingest(d)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.stderrText += String(decoding: d, as: UTF8.self)
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Log.cli.info("claude exited, status \(proc.terminationStatus)")
            let tail = String(self.stderrText.suffix(600))
            DispatchQueue.main.async { self.onExit?(proc.terminationStatus, tail) }
        }
        try p.run()
        process = p
        Log.cli.info("started claude (resume: \(o.resume != nil), fork: \(o.fork))")
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async { [weak self] in self?.dispatch(obj) }
        }
    }

    private func dispatch(_ obj: [String: Any]) {
        if obj["type"] as? String == "control_response", let r = obj["response"] as? [String: Any],
           let id = r["request_id"] as? String, let done = pending.removeValue(forKey: id) {
            done(r["subtype"] as? String == "success" ? (r["response"] as? [String: Any] ?? [:]) : nil)
            return
        }
        onEvent?(obj)
    }

    // MARK: Writing

    /// `content` is a plain string or an array of content blocks (text / image).
    func sendUser(_ content: Any) {
        write(["type": "user", "message": ["role": "user", "content": content]])
    }

    /// Send a control request; `completion` gets the response body, or nil on error.
    func request(_ subtype: String, _ args: [String: Any] = [:], completion: (([String: Any]?) -> Void)? = nil) {
        let id = UUID().uuidString
        if let completion { pending[id] = completion }
        write(["type": "control_request", "request_id": id, "request": ["subtype": subtype].merging(args) { $1 }])
    }

    func respond(_ requestID: String, _ body: [String: Any]) {
        write(["type": "control_response",
               "response": ["subtype": "success", "request_id": requestID, "response": body]])
    }

    func respondError(_ requestID: String, _ message: String) {
        write(["type": "control_response",
               "response": ["subtype": "error", "request_id": requestID, "error": message]])
    }

    func interrupt() { request("interrupt") }

    func stop() {
        onExit = nil; onEvent = nil
        pending.removeAll()
        process?.terminate()
        process = nil; stdin = nil
    }

    private func write(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? stdin?.write(contentsOf: d + Data([0x0A]))
    }
}

// MARK: One-shot helpers (throwaway process; no model call, no session file is created)

extension ClaudeRunner {
    /// Run control requests in order against a short-lived process. `settle` waits before the first
    /// request after `initialize` (MCP servers connect asynchronously).
    @MainActor static func oneShot(cwd: String, _ requests: [(String, [String: Any])], settle: Double = 0) async -> [[String: Any]?] {
        let r = ClaudeRunner()
        guard (try? r.start(Options(cwd: cwd, permission: .manual))) != nil else { return requests.map { _ in nil } }
        defer { r.stop() }
        var out: [[String: Any]?] = []
        for (i, req) in requests.enumerated() {
            if i == 1, settle > 0 { try? await Task.sleep(for: .seconds(settle)) }
            let body: [String: Any]? = await withCheckedContinuation { cont in
                var done = false
                func finish(_ b: [String: Any]?) { if !done { done = true; cont.resume(returning: b) } }
                r.request(req.0, req.1) { finish($0) }
                Task { @MainActor in try? await Task.sleep(for: .seconds(20)); finish(nil) }
            }
            out.append(body)
        }
        return out
    }

    @MainActor static func fetchCatalog(cwd: String) async -> Catalog? {
        guard let b = await oneShot(cwd: cwd, [("initialize", [:])]).first ?? nil else { return nil }
        return Catalog(b)
    }

    /// Rename a session that has no live process, via the CLI's own /rename (so the title lands in its transcript).
    @MainActor static func rename(cwd: String, sessionID: String, to name: String) async -> Bool {
        let r = ClaudeRunner()
        guard (try? r.start(Options(cwd: cwd, permission: .manual, resume: sessionID))) != nil else { return false }
        defer { r.stop() }
        return await withCheckedContinuation { cont in
            var done = false
            func finish(_ ok: Bool) { if !done { done = true; cont.resume(returning: ok) } }
            r.onEvent = { e in
                if e["type"] as? String == "system", e["subtype"] as? String == "session_title_changed" { finish(true) }
                if e["type"] as? String == "result" { finish(false) }
            }
            r.sendUser("/rename \(name)")
            Task { @MainActor in try? await Task.sleep(for: .seconds(20)); finish(false) }
        }
    }
}
