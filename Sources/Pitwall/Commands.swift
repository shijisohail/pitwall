import Foundation
import AppKit

enum SlashRoute { case handled, forward(String) }

enum Shell {
    /// Run a command through the user's login shell, capturing stdout+stderr.
    static func run(_ cmd: String, cwd: String, timeout: Double = 120) async -> (String, Int32) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-l", "-c", cmd]
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            guard (try? p.run()) != nil else { return ("Couldn't run the command.", 127) }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit(); killer.cancel()
            return (String(decoding: data, as: UTF8.self), p.terminationStatus)
        }.value
    }
}

enum TerminalApp {
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static var claude: String { quote(ClaudeRunner.claudePath ?? "claude") }

    /// Opens Terminal running `command` in `cwd` (via a .command file, so no Automation permission is needed).
    static var handoffDir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("pitwall-handoff", isDirectory: true) }

    /// The scripts are only needed for a moment; remove stale ones so they don't pile up in the temp directory.
    static func cleanupHandoffFiles(olderThan age: TimeInterval = 86_400, in dir: URL? = nil) {
        let d = dir ?? handoffDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files where f.pathExtension == "command" {
            let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(m) > age { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Writes the script owner-only (0700, set at creation so it is never briefly readable by others).
    static func writeHandoff(_ command: String, cwd: String, in dir: URL? = nil) -> URL? {
        let dir = dir ?? handoffDir
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let f = dir.appendingPathComponent("\(UUID().uuidString).command")
        let script = "#!/bin/zsh -l\ncd \(quote(cwd)) && \(command)\n"
        guard fm.createFile(atPath: f.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else { return nil }
        return f
    }

    static func run(_ command: String, cwd: String) {
        guard let f = writeHandoff(command, cwd: cwd) else { return }
        NSWorkspace.shared.open(f)
        // Terminal reads the script as it opens; there's no reason to leave it behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { try? FileManager.default.removeItem(at: f) }
    }
}

/// Whether `name` (without the slash) is a command Claude Code or Pitwall would run, ignoring case.
func isKnownCommand(_ name: String, in catalog: Catalog) -> Bool {
    catalog.commands.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        || nativeCommands.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
}

/// Commands Pitwall implements itself because the CLI only runs them in its terminal UI (or because a native UI is nicer).
let nativeCommands: [SlashCommand] = [
    ("clear", "Start a new session in this project"),
    ("resume", "Search and open any past session"),
    ("model", "Show or switch the model"),
    ("effort", "Set the effort level"),
    ("permissions", "View permission rules and switch mode"),
    ("hooks", "View configured hooks"),
    ("config", "View settings, or set key=value"),
    ("memory", "View and open CLAUDE.md memory files"),
    ("status", "Version, model, account and session info"),
    ("mcp", "MCP servers and their tools"),
    ("add-dir", "Give Claude access to another folder"),
    ("plan", "Switch to plan mode"),
    ("rename", "Rename this session"),
    ("export", "Save this conversation as Markdown"),
    ("copy", "Copy the last response"),
    ("branch", "Fork this conversation into a new session"),
    ("fork", "Fork this conversation into a new session"),
    ("diff", "Review uncommitted changes in this project"),
    ("help", "Browse every command and skill"),
    ("skills", "Browse every command and skill"),
    ("review", "Review the current diff (alias of /code-review)"),
    ("btw", "Ask a quick side question without interrupting Claude (works while it is busy)"),
    ("tasks", "Show the commands Claude is running in the background"),
    ("login", "Sign in (opens Terminal)"),
    ("logout", "Sign out (opens Terminal)"),
    ("doctor", "Run diagnostics (opens Terminal)"),
].map { SlashCommand(name: $0.0, description: $0.1, native: true) }

private let terminalOnly: Set<String> = [
    "rewind", "checkpoint", "undo", "ide", "desktop", "app", "theme", "vim",
    "terminal-setup", "tui", "focus", "color", "statusline", "keybindings", "sandbox", "voice", "chrome",
    "remote-control", "rc", "teleport", "tp", "mobile", "ios", "android", "stickers", "radio", "powerup",
    "scroll-speed", "release-notes", "insights", "remote-env", "privacy-settings", "heapdump", "background",
]

extension Conversation {
    func routeSlash(_ text: String) -> SlashRoute {
        let body = text.dropFirst()
        let name = String(body.prefix { !$0.isWhitespace }).lowercased()
        let args = String(body.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
        guard let store else { return .forward(text) }

        switch name {
        case "clear", "new":
            if !args.isEmpty, let sid = sessionID, runner?.isAlive != true {
                Task { _ = await ClaudeRunner.rename(cwd: cwd, sessionID: sid, to: args) }
            }
            store.newConversation(cwd: cwd)
        case "resume": store.sheet = .switcher
        case "model":
            if args.isEmpty {
                let list = (store.catalogs[cwd]?.models ?? []).map { "• `\($0.value)` — \($0.name)" }.joined(separator: "\n")
                card("/model", "**Current:** \(modelName ?? model)\n\nSwitch with `/model <name>` or the model menu under the prompt.\n\n\(list)")
            } else { model = args }
        case "effort":
            if args.isEmpty || args == "status" { card("/effort", "**Current effort:** \(effort ?? "auto")\n\nUse `/effort low|medium|high|xhigh|max|auto`.") }
            else { setEffort(args == "auto" ? nil : args); note("Effort set to \(args)") }
        case "permissions": store.sheet = .config("permissions")
        case "hooks": store.sheet = .config("hooks")
        case "config": if args.isEmpty { store.sheet = .config("all") } else { return .forward(text) }
        case "memory": store.sheet = .memory
        case "status": store.sheet = .status
        case "mcp": if args.isEmpty { store.sheet = .mcp } else { return .forward(text) }
        case "btw": if args.isEmpty { note("Usage: /btw <question>. It is answered on the side, without interrupting Claude.") } else { askSide(args) }
        case "tasks", "bashes": tasksExpanded = true; if tasks.isEmpty { note("No background commands are running.") }
        case "add-dir":
            let p = NSString(string: args).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                additionalDirs.append(p)
                if runner?.isAlive == true { needsRestart = true }
                note("Added \(p.replacingOccurrences(of: NSHomeDirectory(), with: "~")) to this session")
            } else { note("Usage: /add-dir <folder path>") }
        case "plan":
            permission = .plan
            if !args.isEmpty { send(args) } else { note("Plan mode on: Claude will explore and propose a plan before editing") }
        case "rename":
            if runner?.isAlive == true, !args.isEmpty { return .forward(text) }
            guard !args.isEmpty else { note("Usage: /rename <name>"); break }
            title = args
            if let sid = sessionID { Task { _ = await ClaudeRunner.rename(cwd: cwd, sessionID: sid, to: args) } }
        case "export": exportMarkdown(to: args)
        case "copy": copyLastResponse()
        case "branch", "fork":
            if let n = store.fork(self), !args.isEmpty { n.send(args) }
        case "diff": store.sheet = .diff
        case "help", "skills": store.sheet = .commands
        case "review": return .forward("/code-review" + (args.isEmpty ? "" : " " + args))
        case "login": TerminalApp.run("\(TerminalApp.claude) auth login", cwd: cwd)
        case "logout": TerminalApp.run("\(TerminalApp.claude) auth logout", cwd: cwd)
        case "doctor": TerminalApp.run("\(TerminalApp.claude) doctor", cwd: cwd)
        default:
            if terminalOnly.contains(name) {
                note("/\(name) only works in Claude Code's terminal UI. Use Open in Terminal (⇧⌘T) to continue this session there.")
            } else { return .forward(text) }
        }
        return .handled
    }

    // MARK: Terminal handoff

    func openInTerminal() {
        guard !isRunning else { return }
        runner?.stop(); runner = nil
        let cmd = sessionID.map { "\(TerminalApp.claude) --resume \(TerminalApp.quote($0))" } ?? TerminalApp.claude
        TerminalApp.run(cmd, cwd: cwd)
    }

    // MARK: Local shell (`!command`)

    /// `!command`: run it now, beside whatever Claude is doing, with output streaming in, a Stop button, and `cd` carrying
    /// over to the next one. The result is held back and sent to Claude as context with your next message.
    func runLocal(_ cmd: String) {
        var block = Block(kind: .local, toolName: cmd)
        block.live = true
        let m = ChatMessage(role: .assistant, blocks: [block])
        messages.append(m)
        let mid = m.id
        let shell = LiveShell()
        runningShells[mid] = shell
        shell.onOutput = { [weak self] text in self?.setLocalOutput(mid, text, live: true, failed: false) }
        shell.onFinish = { [weak self] text, status, newCwd, stopped in
            guard let self else { return }
            self.runningShells[mid] = nil
            if let d = newCwd, FileManager.default.fileExists(atPath: d) { self.shellCwd = d }
            var shown = text.isEmpty ? (stopped ? "" : "(no output)") : text
            if stopped { shown += (shown.isEmpty ? "" : "\n") + "[stopped]" }
            self.setLocalOutput(mid, shown, live: false, failed: status != 0)
            self.queuedLocal.append("$ \(cmd)\n" + String(text.suffix(3_000)))
        }
        shell.start(cmd, cwd: shellCwd ?? cwd)
    }

    private func setLocalOutput(_ messageID: String, _ text: String, live: Bool, failed: Bool) {
        guard let mi = messages.firstIndex(where: { $0.id == messageID }), !messages[mi].blocks.isEmpty else { return }
        messages[mi].blocks[0].text = text
        messages[mi].blocks[0].live = live ? true : nil
        messages[mi].blocks[0].isError = failed
    }

    /// Stop every `!` command. Each stays registered until it reports back, so its card ends as "[stopped]".
    func stopAllShells() {
        for s in runningShells.values { s.stop() }
    }

    // MARK: Export / copy

    func markdownTranscript() -> String {
        var out = "# \(title)\n\n`\(cwd)`\n\n"
        for m in messages {
            switch m.role {
            case .user:
                out += "## You\n\n" + m.blocks.filter { $0.kind == .text }.map(\.text).joined(separator: "\n\n") + "\n\n"
            case .assistant:
                var parts: [String] = []
                for b in m.blocks {
                    switch b.kind {
                    case .text: parts.append(b.text)
                    case .tool: parts.append("> **\(b.toolName)** `\(b.toolSummary)`")
                    case .output: parts.append("```\n\(b.text)\n```")
                    case .local: parts.append("```\n$ \(b.toolName)\n\(b.text)\n```")
                    case .notice: parts.append("*\(b.text)*")
                    case .error: parts.append("**Error:** \(b.text)")
                    default: break
                    }
                }
                if !parts.isEmpty { out += "## Claude\n\n" + parts.joined(separator: "\n\n") + "\n\n" }
            }
        }
        return out
    }

    func exportMarkdown(to name: String) {
        let md = markdownTranscript()
        if !name.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: name).expandingTildeInPath,
                          relativeTo: URL(fileURLWithPath: cwd)).standardized
            do { try md.write(to: url, atomically: true, encoding: .utf8); note("Exported to \(url.path)") }
            catch { note("Couldn't write \(url.path)") }
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".md"
        if panel.runModal() == .OK, let url = panel.url { try? md.write(to: url, atomically: true, encoding: .utf8) }
    }

    func copyLastResponse() {
        guard let m = messages.last(where: { $0.role == .assistant && $0.blocks.contains { $0.kind == .text } }) else {
            note("Nothing to copy yet"); return
        }
        let t = m.blocks.filter { $0.kind == .text }.map(\.text).joined(separator: "\n\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
        note("Copied the last response")
    }
}

extension Conversation {
    func promptRename() {
        let a = NSAlert()
        a.messageText = "Rename session"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        f.stringValue = title
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty else { return }
        let name = f.stringValue
        title = name
        if runner?.isAlive == true { if !isRunning { send("/rename \(name)") } }   // the CLI records it in the transcript
        else { _ = routeSlash("/rename \(name)") }
    }
}
