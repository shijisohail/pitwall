import Foundation
import AppKit

/// Git worktrees for parallel sessions. `claude --worktree <name>` gives a session its own checkout of the repository
/// under `<repo>/.claude/worktrees/<name>` on a new branch `worktree-<name>`, so two sessions in one project cannot
/// overwrite each other's files. Verified live against Claude Code 2.1.319 (docs/CLAUDE_CODE_PROTOCOL.md).
enum Worktrees {
    static let marker = "/.claude/worktrees/"

    /// `/repo/.claude/worktrees/fix-login` → "fix-login". Anything else → nil.
    static func name(inPath p: String) -> String? {
        guard let r = p.range(of: marker) else { return nil }
        let first = p[r.upperBound...].split(separator: "/", omittingEmptySubsequences: true).first
        return first.map(String.init)
    }

    /// `/repo/.claude/worktrees/fix-login` → "/repo". Anything else → nil.
    static func root(ofPath p: String) -> String? {
        guard let r = p.range(of: marker), r.lowerBound != p.startIndex else { return nil }
        return String(p[..<r.lowerBound])
    }

    /// Where the CLI puts a worktree.
    static func path(root: String, name: String) -> String { root + marker + name }

    /// A name that is safe as a directory and as part of a branch name: letters, digits, `.`, `_`, `-`. Spaces and
    /// slashes become one dash; everything else is dropped.
    static func sanitize(_ raw: String) -> String {
        var out = ""
        for ch in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isASCII, ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." {
                out.append(ch)
            } else if ch == " " || ch == "/" || ch == "\\" {
                if out.last != "-" { out.append("-") }
            }
        }
        while out.contains("..") { out = out.replacingOccurrences(of: "..", with: ".") }
        while let f = out.first, f == "." || f == "-" { out.removeFirst() }
        out = String(out.prefix(48))
        while let l = out.last, l == "." || l == "-" { out.removeLast() }
        if out.hasSuffix(".lock") { out.removeLast(5) }
        return out
    }

    /// "pitwall-k3x9". Injectable for tests.
    static func suggestedName(random: () -> Int = { Int.random(in: 0..<Int.max) }) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var n = random(), s = ""
        for _ in 0..<4 { s.append(alphabet[n % alphabet.count]); n /= alphabet.count }
        return "pitwall-" + s
    }

    // MARK: git

    /// Runs `git -C dir args…` through a login shell (so Homebrew's git is found, as for `claude`) and returns its
    /// combined output. `GIT_OPTIONAL_LOCKS=0` keeps a `status` from fighting a running Claude over the index.
    nonisolated static func git(_ args: [String], in dir: String) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "exec \"$0\" \"$@\"", "git", "-C", dir] + args
        p.environment = ProcessInfo.processInfo.environment.merging(["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]) { $1 }
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isGitRepo(_ dir: String) async -> Bool {
        await Task.detached { git(["rev-parse", "--is-inside-work-tree"], in: dir) == (0, "true") }.value
    }

    /// Changed or untracked files in a checkout, or nil if git could not say.
    static func changedFiles(at path: String) async -> Int? {
        await Task.detached {
            let r = git(["status", "--porcelain"], in: path)
            return r.status == 0 ? r.output.split(separator: "\n").count : nil
        }.value
    }

    enum RemoveResult: Equatable {
        case removed(branchKept: Bool)
        case failed(String)
    }

    /// Removes the worktree directory and, when git considers it fully merged, its `worktree-<name>` branch. A branch with
    /// commits that exist nowhere else is kept, so no work is lost that the user did not explicitly discard with `force`.
    /// `-p` runs leave Claude's lock on the worktree, so it is released first.
    static func remove(path: String, force: Bool) async -> RemoveResult {
        guard let root = root(ofPath: path), let name = name(inPath: path) else { return .failed("This is not a Claude Code worktree.") }
        return await Task.detached {
            _ = git(["worktree", "unlock", path], in: root)
            let r = git(["worktree", "remove"] + (force ? ["--force"] : []) + [path], in: root)
            guard r.status == 0 else { return .failed(r.output.isEmpty ? "git could not remove the worktree." : r.output) }
            let b = git(["branch", "-d", "worktree-" + name], in: root)
            return .removed(branchKept: b.status != 0 && b.output.contains("not fully merged"))
        }.value
    }
}

// MARK: Conversation

extension Conversation {
    /// The worktree this session works in, or the one it will start in.
    var worktreeLabel: String? { Worktrees.name(inPath: cwd) ?? worktreeName }
    var inWorktree: Bool { Worktrees.name(inPath: cwd) != nil }

    /// A worktree can only be chosen before the session exists: `--worktree` is a launch option.
    var canChooseWorktree: Bool {
        sessionID == nil && messages.isEmpty && runner == nil && !inWorktree && historyPath == nil && loadState == .loaded
    }

    /// The folder to launch `claude` in. A session's worktree may have been deleted since; the CLI then resumes it in the
    /// launch directory and says so, so fall back to the repository the worktree belonged to.
    var launchDirectory: String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cwd), let root = Worktrees.root(ofPath: cwd), fm.fileExists(atPath: root) { return root }
        return cwd
    }

    /// Flags for `claude` that this session's worktree choice needs. Only a brand-new session gets one.
    var worktreeArguments: [String] {
        guard let n = worktreeName, !n.isEmpty, sessionID == nil, forkFrom == nil else { return [] }
        return ["--worktree", n]
    }

    /// The CLI reports the folder it actually works in. For a worktree session that is the worktree, and from then on every
    /// git, file and terminal feature of this session should look there rather than at the main checkout.
    func adoptWorkingDirectory(_ reported: String) {
        guard reported != cwd, Worktrees.name(inPath: reported) != nil else { return }
        let old = cwd
        cwd = reported
        if let cat = store?.catalogs[old] { store?.catalogs[reported] = cat }
    }

    /// Switch "run in its own worktree" on or off for a session that has not started.
    func toggleWorktree() {
        guard canChooseWorktree else { return }
        if worktreeName != nil { worktreeName = nil; return }
        let dir = cwd
        Task { [weak self] in
            let ok = await Worktrees.isGitRepo(dir)
            guard let self, self.canChooseWorktree else { return }
            if ok { self.worktreeName = Worktrees.suggestedName() }
            else { Self.alert("Worktrees need a git repository", "\((dir as NSString).lastPathComponent) isn't one, so this session can't get its own checkout.") }
        }
    }

    func revealWorktree() {
        guard inWorktree else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    /// Delete this session's worktree after confirming. Uncommitted work is only discarded when the user agrees to it.
    func removeWorktree() {
        guard let name = Worktrees.name(inPath: cwd), !isRunning else { return }
        let path = cwd
        Task { [weak self] in
            let changed = await Worktrees.changedFiles(at: path)
            guard let self else { return }
            let a = NSAlert()
            a.messageText = "Remove worktree “\(name)”?"
            switch changed {
            case .some(let n) where n > 0:
                a.informativeText = "\(n) changed or untracked file\(n == 1 ? "" : "s") in it will be lost. The session's history stays."
            case .some:
                a.informativeText = "It has no uncommitted work. Its branch worktree-\(name) is deleted too, unless it holds commits that exist nowhere else. The session's history stays."
            case .none:
                a.informativeText = "Git couldn't check it for uncommitted work, so it is removed only if git agrees it is clean."
            }
            a.alertStyle = .warning
            a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            self.runner?.stop(); self.runner = nil; self.isRunning = false; self.turnStart = nil
            self.endAllTasks(); self.endAllWorkflows()
            switch await Worktrees.remove(path: path, force: (changed ?? 0) > 0) {
            case .removed(let kept):
                self.note("Removed worktree \(name)." + (kept ? " Branch worktree-\(name) was kept because it has unmerged commits." : ""))
            case .failed(let why):
                self.note("Couldn't remove worktree \(name): \(why)")
            }
        }
    }

    @MainActor static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}

// MARK: Store

extension Store {
    /// "New Session in Worktree…": asks for a name, checks the folder is a git repository, then opens a session that will
    /// start with `claude --worktree <name>`.
    func newWorktreeConversation(cwd: String? = nil) {
        guard let dir = cwd ?? current?.cwd ?? projects.first?.path else { sheet = .projects; return }
        let a = NSAlert()
        a.messageText = "New session in its own worktree"
        a.informativeText = "Claude works in a separate checkout of \((dir as NSString).lastPathComponent) on its own branch, so it can't collide with other sessions here."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        f.stringValue = Worktrees.suggestedName()
        a.accessoryView = f
        a.addButton(withTitle: "Start"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = Worktrees.sanitize(f.stringValue).isEmpty ? Worktrees.suggestedName() : Worktrees.sanitize(f.stringValue)
        Task { [weak self] in
            guard await Worktrees.isGitRepo(dir) else {
                Conversation.alert("Worktrees need a git repository", "\((dir as NSString).lastPathComponent) isn't one.")
                return
            }
            guard let self else { return }
            if self.owner(ofPath: dir) == nil { self.workspace.append(dir) }
            let c = Conversation(cwd: dir)
            c.store = self; c.worktreeName = name
            self.conversations.append(c); self.open(c)
        }
    }
}
