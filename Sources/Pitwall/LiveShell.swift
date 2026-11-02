import Foundation

/// A `!command` run live, like the terminal's shell mode: output streams in as it is produced, it can be stopped
/// (the whole process tree, not just the shell), and a `cd` carries over to the next command.
@MainActor
final class LiveShell {
    static let marker = "__PITWALL_CWD__"
    /// The display and the saved context keep only this much of a command's output.
    static let displayLimit = 20_000
    private static let rawLimit = 2_000_000

    private let process = Process()
    private let pipe = Pipe()
    private var raw = Data()
    private var lastPush = Date.distantPast
    private var pushScheduled = false
    private var exited = false
    private var sawEOF = false
    private var done = false
    private(set) var stopped = false

    /// The command's output so far (the folder marker is never shown).
    var onOutput: ((String) -> Void)?
    /// Output, exit status, the folder the command ended in (nil if it never got to report), and whether it was stopped.
    var onFinish: ((_ output: String, _ status: Int32, _ cwd: String?, _ stopped: Bool) -> Void)?

    // MARK: Script and parsing (pure, tested)

    /// `cmd` run in `dir`, followed by a line reporting the folder it finished in, with `cmd`'s own exit status kept.
    static func script(_ cmd: String, in dir: String) -> String {
        "cd \(TerminalApp.quote(dir)) 2>/dev/null\n{ \(cmd)\n}; __pw=$?; printf '\\n\(marker)%s\\n' \"$PWD\"; exit $__pw"
    }

    /// Splits the raw output into what to show and the reported folder.
    static func split(_ text: String) -> (output: String, cwd: String?) {
        guard let r = text.range(of: "\n" + marker, options: .backwards) else { return (trimTrailingNewlines(text), nil) }
        let cwd = text[r.upperBound...].prefix { $0 != "\n" }
        return (trimTrailingNewlines(String(text[..<r.lowerBound])), cwd.isEmpty ? nil : String(cwd))
    }

    private static func trimTrailingNewlines(_ s: String) -> String {
        var t = Substring(s)
        while t.last == "\n" || t.last == "\r" { t = t.dropLast() }
        return String(t)
    }

    // MARK: Running

    func start(_ cmd: String, cwd: String) {
        var dir = cwd
        if !FileManager.default.fileExists(atPath: dir) { dir = NSHomeDirectory() }
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", Self.script(cmd, in: dir)]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice          // a command that reads input gets EOF instead of hanging
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { d.isEmpty ? self?.endOfOutput() : self?.append(d) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processExited() } }
        }
        do { try process.run() }
        catch { finish(status: 127, text: "Couldn't run the command.") }
    }

    func stop() {
        guard !done, process.isRunning else { return }
        stopped = true
        Self.killTree(process.processIdentifier, signal: SIGTERM)
        let pid = process.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in        // anything that ignored SIGTERM
            MainActor.assumeIsolated { if self?.done == false { Self.killTree(pid, signal: SIGKILL) } }
        }
    }

    /// Signals `pid` and every descendant, leaves first, so a `sleep` or dev server behind the shell does not outlive Stop.
    nonisolated static func killTree(_ pid: pid_t, signal: Int32) {
        var children: [pid_t: [pid_t]] = [:]
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-axo", "pid=,ppid="]
        let out = Pipe(); ps.standardOutput = out
        if (try? ps.run()) != nil {
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            for line in text.split(separator: "\n") {
                let f = line.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
                if f.count == 2 { children[f[1], default: []].append(f[0]) }
            }
        }
        func descendants(_ p: pid_t) -> [pid_t] { (children[p] ?? []).flatMap { descendants($0) + [$0] } }
        for p in descendants(pid) + [pid] { kill(p, signal) }
    }

    // MARK: Output

    private func append(_ d: Data) {
        raw.append(d)
        if raw.count > Self.rawLimit { raw = raw.suffix(Self.rawLimit / 2) }
        let now = Date()
        if now.timeIntervalSince(lastPush) > 0.1 { push() }
        else if !pushScheduled {
            pushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MainActor.assumeIsolated { self?.pushScheduled = false; self?.push() }
            }
        }
    }

    private func push() {
        guard !done else { return }
        lastPush = Date()
        onOutput?(Self.clip(Self.split(String(decoding: raw, as: UTF8.self)).output))
    }

    private static func clip(_ s: String) -> String { s.count > displayLimit ? "…" + s.suffix(displayLimit) : s }

    private func endOfOutput() { sawEOF = true; if exited { finish() } }

    private func processExited() {
        exited = true
        if sawEOF { finish(); return }
        // A background child can hold the pipe open after the command itself is done: don't wait for it forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in MainActor.assumeIsolated { self?.finish() } }
    }

    private func finish(status: Int32? = nil, text: String? = nil) {
        guard !done else { return }
        done = true
        pipe.fileHandleForReading.readabilityHandler = nil
        let parts = Self.split(text ?? String(decoding: raw, as: UTF8.self))
        onFinish?(Self.clip(parts.output), status ?? process.terminationStatus, parts.cwd, stopped)
    }
}
