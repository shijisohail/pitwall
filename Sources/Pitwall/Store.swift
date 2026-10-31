import AppKit
import Observation

struct Project: Identifiable, Hashable {
    var path: String
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var shortPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

struct RecentProject: Identifiable {
    var path: String
    var count: Int
    var last: Date
    var id: String { path }
}

enum SheetKind: Identifiable, Hashable {
    case switcher, commands, mcp, memory, diff, status, projects, config(String)
    var id: String {
        switch self {
        case .config(let t): "config-\(t)"
        default: "\(self)"
        }
    }
}

@MainActor @Observable
final class Store {
    static let shared = Store()

    var conversations: [Conversation] = []
    var selection: String? {
        didSet {
            conversations.first { $0.id == oldValue }?.stopTail()
            guard let c = current else { return }
            c.loadHistoryIfNeeded(); c.startTail(); ensureCatalog(c.cwd)
        }
    }
    var query = ""
    var showBoard = true
    var isScanning = false
    var catalogs: [String: Catalog] = [:]
    var usage: Usage?
    var sheet: SheetKind?
    var composerInsert: String?
    var focusProject: String?
    var showAutomation = false {
        didSet { defaults.set(showAutomation, forKey: "showAutomation") }
    }
    /// The folders the user chose to open. Only sessions under these are shown or loaded.
    var workspace: [String] = [] {
        didSet { defaults.set(workspace, forKey: "workspace") }
    }
    /// Open tabs (conversation ids), left to right.
    var tabs: [String] = [] {
        didSet { persistTabs() }
    }

    private var prompts: [History.PromptEntry] = []
    private var owned: Set<String> = []
    private var loadingCatalogs: Set<String> = []
    private var didInitialSelect = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showAutomation = defaults.bool(forKey: "showAutomation")
        workspace = defaults.stringArray(forKey: "workspace") ?? []
        tabs = defaults.stringArray(forKey: "tabs") ?? []
        owned = Set(defaults.stringArray(forKey: "pitwallOwned") ?? [])
    }

    private func isOwned(_ c: Conversation) -> Bool { owned.contains(c.id) || (c.sessionID.map { owned.contains($0) } ?? false) }

    /// A session created in Pitwall gets a different id on disk once it has run, so persist the durable (session) id.
    func persistTabs() {
        defaults.set(tabs.map { id in conversations.first { $0.id == id }?.sessionID ?? id }, forKey: "tabs")
    }

    var current: Conversation? { conversations.first { $0.id == selection } }
    func catalog(_ cwd: String) -> Catalog { catalogs[cwd] ?? Catalog() }

    // MARK: Workspace scoping

    /// The opened folder a path belongs to (the deepest match), or nil if it's outside the workspace.
    func owner(ofPath p: String) -> String? {
        workspace.filter { p == $0 || p.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }
    func owner(_ c: Conversation) -> String? { owner(ofPath: c.cwd) }

    /// "Claude Code history only": hide sessions started by scripts/SDK runs, except ones Pitwall started itself.
    private func isVisible(_ c: Conversation, scoped: Bool) -> Bool {
        if scoped, owner(c) == nil { return false }
        if c.id == selection { return true }
        if c.historyPath == nil { return !c.messages.isEmpty }
        if c.entrypoint == "sdk-cli", !showAutomation, !isOwned(c) { return false }
        return true
    }

    var hiddenAutomationCount: Int {
        conversations.filter { owner($0) != nil && $0.entrypoint == "sdk-cli" && !isOwned($0) }.count
    }

    // MARK: Derived

    var filtered: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = conversations.filter { isVisible($0, scoped: true) }
        guard !q.isEmpty else { return visible.sorted { $0.updatedAt > $1.updatedAt } }
        return visible.filter { $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q) || $0.searchText.contains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Search for the ⌘K switcher; `all` reaches past the opened projects.
    func search(_ query: String, all: Bool = false) -> [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = conversations.filter { isVisible($0, scoped: !all) }.sorted { $0.updatedAt > $1.updatedAt }
        guard !q.isEmpty else { return visible }
        return visible.filter { $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q) || $0.searchText.contains(q) }
    }

    var projects: [Project] {
        var latest: [String: Date] = [:]
        if query.isEmpty { for p in workspace { latest[p] = .distantPast } }
        for c in filtered { if let o = owner(c) { latest[o] = max(latest[o] ?? .distantPast, c.updatedAt) } }
        return latest.sorted { $0.value > $1.value }.map { Project(path: $0.key) }
    }

    func conversations(in p: Project) -> [Conversation] { filtered.filter { owner($0) == p.path } }

    /// Folders Claude Code has history for that aren't open yet, newest first.
    func recentProjects() -> [RecentProject] {
        var d: [String: (Int, Date)] = [:]
        for c in conversations where c.historyPath != nil && isVisible(c, scoped: false) {
            let e = d[c.cwd] ?? (0, .distantPast)
            d[c.cwd] = (e.0 + 1, max(e.1, c.updatedAt))
        }
        return d.filter { owner(ofPath: $0.key) == nil && FileManager.default.fileExists(atPath: $0.key) }
            .map { RecentProject(path: $0.key, count: $0.value.0, last: $0.value.1) }
            .sorted { $0.last > $1.last }
    }

    /// Past prompts for the composer's ↑ history, newest first, scoped to a project.
    func promptHistory(for cwd: String) -> [String] {
        var seen = Set<String>()
        return prompts.filter { $0.project == cwd }.sorted { $0.ts > $1.ts }
            .compactMap { seen.insert($0.text).inserted && !$0.text.hasPrefix("/") ? $0.text : nil }
    }

    // MARK: Scanning

    func scan() async {
        if conversations.isEmpty { isScanning = true }
        let (metas, entries) = await Task.detached(priority: .utility) { History.scanAll() }.value
        prompts = entries
        var byID: [String: Conversation] = [:]
        for c in conversations { byID[c.id] = c; if let s = c.sessionID { byID[s] = c } }
        for m in metas {
            if let c = byID[m.id] { c.update(from: m) }
            else { let c = Conversation(meta: m); c.store = self; conversations.append(c) }
        }
        // Drop tabs whose session vanished or whose folder was closed.
        tabs.removeAll { id in conversations.first { $0.id == id }.map { owner($0) == nil } ?? true }
        persistTabs()
        if !didInitialSelect {
            didInitialSelect = true
            if selection == nil { selection = tabs.first ?? filtered.first?.id }
        }
        Log.history.info("scanned \(metas.count) sessions")
        isScanning = false
    }

    func ensureCatalog(_ cwd: String) {
        guard catalogs[cwd] == nil, !loadingCatalogs.contains(cwd) else { return }
        loadingCatalogs.insert(cwd)
        Task {
            if let c = await ClaudeRunner.fetchCatalog(cwd: cwd) { catalogs[cwd] = c }
            loadingCatalogs.remove(cwd)
        }
    }

    func updateUsage(_ e: [String: Any]) {
        guard let w = (e["rate_limit_info"] as? [String: Any])?["unifiedWindows"] as? [String: Any] else { return }
        func win(_ k: String) -> (Double, Date?)? {
            guard let d = w[k] as? [String: Any], let u = d["utilization"] as? Double else { return nil }
            return (u, (d["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) })
        }
        let f = win("five_hour"), s = win("seven_day")
        usage = Usage(fiveHour: f?.0 ?? usage?.fiveHour ?? 0, sevenDay: s?.0 ?? usage?.sevenDay ?? 0,
                      fiveReset: f?.1 ?? usage?.fiveReset, sevenReset: s?.1 ?? usage?.sevenReset)
    }

    func markOwned(_ id: String) {
        guard owned.insert(id).inserted else { return }
        defaults.set(Array(owned), forKey: "pitwallOwned")
    }

    // MARK: Actions

    /// Open a session in the session screen (leaves Pit Wall). Pulls its folder into the workspace if needed.
    func open(_ c: Conversation) {
        if owner(c) == nil { workspace.append(c.cwd) }
        if !tabs.contains(c.id) { tabs.append(c.id) }
        selection = c.id; showBoard = false
    }

    // MARK: Tabs

    func selectTab(_ id: String) { selection = id; showBoard = false }

    /// Closing a tab never stops a session; it keeps working in the background (see Pit Wall).
    func closeTab(_ id: String) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        if let c = conversations.first(where: { $0.id == id }), c.historyPath == nil, c.messages.isEmpty, c.sessionID == nil {
            c.teardown(); conversations.removeAll { $0.id == id }      // an untouched blank session isn't worth keeping
        }
        if selection == id {
            if tabs.isEmpty { selection = nil; showBoard = true } else { selection = tabs[min(i, tabs.count - 1)] }
        }
    }

    func closeCurrentTab() {
        if !showBoard, let s = selection { closeTab(s) } else { NSApp.keyWindow?.performClose(nil) }
    }

    func closeOtherTabs(_ keep: String) { tabs.filter { $0 != keep }.forEach(closeTab); selectTab(keep) }

    func closeTabs(after id: String) {
        guard let i = tabs.firstIndex(of: id) else { return }
        Array(tabs.suffix(from: i + 1)).forEach(closeTab)
    }

    func cycleTab(_ d: Int) {
        guard !tabs.isEmpty else { return }
        let i = tabs.firstIndex(of: selection ?? "") ?? (d > 0 ? -1 : 0)
        selectTab(tabs[(i + d + tabs.count) % tabs.count])
    }

    func moveTab(_ id: String, before target: String) {
        guard id != target, let from = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: from)
        tabs.insert(id, at: tabs.firstIndex(of: target) ?? tabs.endIndex)
    }

    /// Choose a folder with the system picker.
    func pickProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Open Project"; panel.message = "Choose one or more folders for Claude to work in"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { openFolder($0.path) }
    }

    /// Add a folder to the workspace and show it: its sessions on Pit Wall, or a fresh session if it has none.
    func openFolder(_ raw: String) {
        let path = (raw as NSString).standardizingPath
        if owner(ofPath: path) != path { workspace.append(path) }
        let own = conversations.filter { owner($0) == path }
        focusProject = path
        if own.contains(where: { $0.historyPath != nil }) { showBoard = true; selection = filtered.first { owner($0) == path }?.id ?? selection }
        else { newConversation(cwd: path) }
    }

    /// Remove a folder from the workspace. Nothing is deleted; its sessions just stop being shown or loaded.
    func closeFolder(_ path: String) {
        let affected = conversations.filter { owner($0) == path }
        let running = affected.filter(\.isRunning)
        if !running.isEmpty {
            let a = NSAlert()
            a.messageText = "Close \((path as NSString).lastPathComponent)?"
            a.informativeText = "\(running.count) session\(running.count == 1 ? " is" : "s are") still working and will be stopped. Their history stays on disk."
            a.addButton(withTitle: "Stop & Close"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        affected.forEach { $0.teardown() }
        let closedIDs = Set(affected.map(\.id))
        tabs.removeAll { closedIDs.contains($0) }
        let gone = Set(affected.filter { $0.historyPath == nil && $0.messages.isEmpty }.map(\.id))
        conversations.removeAll { gone.contains($0.id) }
        workspace.removeAll { $0 == path }
        if focusProject == path { focusProject = nil }
        if let s = current, owner(s) == nil { selection = filtered.first?.id; showBoard = true }
    }

    func newConversation(cwd: String? = nil) {
        guard let dir = cwd ?? current?.cwd ?? projects.first?.path else { sheet = .projects; return }
        if owner(ofPath: dir) == nil { workspace.append(dir) }
        // Reuse an untouched empty session instead of piling up blanks.
        if let blank = conversations.first(where: { $0.cwd == dir && $0.historyPath == nil && $0.messages.isEmpty && $0.sessionID == nil }) {
            open(blank); return
        }
        let c = Conversation(cwd: dir)
        c.store = self
        conversations.append(c); open(c)
    }

    @discardableResult
    func fork(_ c: Conversation) -> Conversation? {
        guard let sid = c.sessionID else { c.note("Send a message first; there's nothing to fork yet."); return nil }
        let n = Conversation(cwd: c.cwd)
        n.store = self; n.messages = c.messages; n.title = c.title + " (fork)"; n.branch = c.branch
        n.forkFrom = sid; n.model = c.model; n.permission = c.permission; n.effort = c.effort
        conversations.append(n); open(n)
        return n
    }

    func remove(_ c: Conversation) {
        guard c.historyPath == nil else { return }   // never touch Claude Code's own files
        c.teardown()
        conversations.removeAll { $0.id == c.id }
        if selection == c.id { selection = filtered.first?.id }
    }
}
