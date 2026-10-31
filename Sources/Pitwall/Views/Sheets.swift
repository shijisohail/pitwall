import SwiftUI
import AppKit

private struct SheetFrame<Content: View>: View {
    let title: String
    var width: CGFloat = 600
    var height: CGFloat = 540
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }.padding([.horizontal, .top], 20).padding(.bottom, 12)
            content
        }
        .frame(width: width, height: height)
        .background { AuroraBackground() }
    }
}

struct SheetHost: View {
    let kind: SheetKind
    var body: some View {
        switch kind {
        case .switcher: SwitcherSheet()
        case .commands: CommandsSheet()
        case .mcp: MCPSheet()
        case .memory: MemorySheet()
        case .diff: DiffSheet()
        case .status: StatusSheet()
        case .projects: ProjectsSheet()
        case .config(let tab): ConfigSheet(tab: tab)
        }
    }
}

// MARK: Quick switcher (⌘K, /resume)

struct SwitcherSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var idx = 0
    @FocusState private var focused: Bool

    @State private var all = false
    private var results: [Conversation] { Array(store.search(q, all: all).prefix(60)) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search sessions and prompts…", text: $q)
                .textFieldStyle(.plain).font(.system(size: 18)).padding(18).focused($focused)
                .onSubmit { open(idx) }
                .onKeyPress(.downArrow) { idx = min(idx + 1, results.count - 1); return .handled }
                .onKeyPress(.upArrow) { idx = max(idx - 1, 0); return .handled }
                .onChange(of: q) { idx = 0 }
            HStack {
                Toggle("Search all projects, not just the ones I've opened", isOn: $all).toggleStyle(.switch).controlSize(.small).font(.caption)
                Spacer()
            }.padding(.horizontal, 18).padding(.bottom, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, c in
                            Button { open(i) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).lineLimit(1)
                                        Text((c.cwd as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(relativeTime(c.updatedAt)).font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                                .background(i == idx ? Color.accentColor.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).id(i)
                        }
                    }.padding(8)
                }
                .onChange(of: idx) { proxy.scrollTo(idx) }
            }
        }
        .frame(width: 640, height: 460)
        .background { AuroraBackground() }
        .onAppear { focused = true }
    }

    private func open(_ i: Int) {
        guard let c = results[safe: i] else { return }
        store.open(c); dismiss()
    }
}

// MARK: Commands & skills browser (/help, /skills)

struct CommandsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    private let builtin: Set<String> = ["compact", "context", "cost", "usage", "model", "effort", "clear", "rename", "mcp", "code-review",
                                        "init", "security-review", "fast", "goal", "output-style", "config", "agents", "doctor", "review"]

    private var all: [SlashCommand] {
        var by: [String: SlashCommand] = [:]
        for c in store.catalog(store.current?.cwd ?? "").commands { by[c.name] = c }
        for c in nativeCommands { by[c.name] = c }
        let f = q.lowercased()
        return by.values.filter { f.isEmpty || $0.name.lowercased().contains(f) || $0.description.lowercased().contains(f) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        SheetFrame(title: "Commands & Skills", width: 680, height: 600) {
            TextField("Filter…", text: $q).textFieldStyle(.roundedBorder).padding(.horizontal, 20)
            List {
                Section("Commands") { ForEach(all.filter { $0.native || builtin.contains($0.name) }) { row($0) } }
                Section("Skills, custom commands & plugins") { ForEach(all.filter { !$0.native && !builtin.contains($0.name) }) { row($0) } }
            }.scrollContentBackground(.hidden)
        }
    }

    private func row(_ c: SlashCommand) -> some View {
        Button { store.composerInsert = "/\(c.name) "; dismiss() } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("/" + c.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if !c.hint.isEmpty { Text(c.hint).font(.caption).foregroundStyle(.tertiary) }
                }
                Text(c.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: MCP

struct MCPSheet: View {
    @Environment(Store.self) private var store
    @State private var servers: [[String: Any]]?
    @State private var failed = false

    var body: some View {
        SheetFrame(title: "MCP Servers", width: 620, height: 560) {
            if let servers {
                List(Array(servers.enumerated()), id: \.offset) { _, s in
                    let status = s["status"] as? String ?? "unknown"
                    let tools = (s["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    DisclosureGroup {
                        Text(tools.isEmpty ? "No tools loaded" : tools.joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(status == "connected" ? .green : status == "needs-auth" ? .orange : status == "pending" ? .yellow : .red)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s["name"] as? String ?? "").fontWeight(.medium)
                                Text("\(status) · \(s["transport"] as? String ?? "") · \(s["source"] as? String ?? s["scope"] as? String ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !tools.isEmpty { Text("\(tools.count) tools").font(.caption).foregroundStyle(.tertiary) }
                        }
                    }
                }.scrollContentBackground(.hidden)
            } else if failed {
                ContentUnavailableView("Couldn't read MCP status", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Connecting to servers…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let c = store.current else { failed = true; return }
        if let r = c.runner, r.isAlive {
            r.request("mcp_status") { b in servers = b?["mcpServers"] as? [[String: Any]]; failed = servers == nil }
        } else {
            let res = await ClaudeRunner.oneShot(cwd: c.cwd, [("initialize", [:]), ("mcp_status", [:])], settle: 3)
            servers = res.last??["mcpServers"] as? [[String: Any]]
            failed = servers == nil
        }
    }
}

// MARK: Memory

struct MemorySheet: View {
    @Environment(Store.self) private var store

    private struct Item: Identifiable { var id: String { path }; var label: String; var path: String }

    private var items: [Item] {
        let cwd = store.current?.cwd ?? NSHomeDirectory()
        let home = NSHomeDirectory()
        let encoded = cwd.map { "/.".contains($0) ? "-" : String($0) }.joined()
        var list = [Item(label: "User memory", path: "\(home)/.claude/CLAUDE.md"),
                    Item(label: "Project memory", path: "\(cwd)/CLAUDE.md"),
                    Item(label: "Project memory (.claude)", path: "\(cwd)/.claude/CLAUDE.md"),
                    Item(label: "Local memory", path: "\(cwd)/CLAUDE.local.md")]
        let auto = "\(home)/.claude/projects/\(encoded)/memory"
        list.append(Item(label: "Auto memory index", path: "\(auto)/MEMORY.md"))
        if let files = try? FileManager.default.contentsOfDirectory(atPath: auto) {
            for f in files.sorted() where f.hasSuffix(".md") && f != "MEMORY.md" { list.append(Item(label: "Auto memory", path: "\(auto)/\(f)")) }
        }
        return list
    }

    var body: some View {
        SheetFrame(title: "Memory", width: 640, height: 560) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items) { it in
                        let text = try? String(contentsOfFile: it.path, encoding: .utf8)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(it.label).fontWeight(.semibold)
                                Spacer()
                                if text != nil { Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: it.path)) }.buttonStyle(HTBSecondary()).controlSize(.small) }
                            }
                            Text(it.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            if let text {
                                Text(text.components(separatedBy: "\n").prefix(10).joined(separator: "\n"))
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(10)
                            } else { Text("Not created").font(.caption).foregroundStyle(.tertiary) }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(16)
                    }
                }.padding(20)
            }
        }
    }
}

// MARK: Settings viewer (/permissions, /hooks, /config)

struct ConfigSheet: View {
    let tab: String
    @Environment(Store.self) private var store
    @State private var section: String

    init(tab: String) { self.tab = tab; _section = State(initialValue: tab) }

    private var files: [(String, String)] {
        let cwd = store.current?.cwd ?? NSHomeDirectory()
        return [("User", "\(NSHomeDirectory())/.claude/settings.json"),
                ("Project", "\(cwd)/.claude/settings.json"),
                ("Local", "\(cwd)/.claude/settings.local.json")]
    }

    var body: some View {
        SheetFrame(title: "Settings", width: 680, height: 600) {
            Picker("", selection: $section) {
                Text("Permissions").tag("permissions"); Text("Hooks").tag("hooks"); Text("Everything").tag("all")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 10) {
                    if section == "permissions", let c = store.current { modePicker(c) }
                    ForEach(files, id: \.1) { label, path in
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let shown = section == "all" ? o : o.filter { $0.key == section }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(label) settings").fontWeight(.semibold)
                                    Spacer()
                                    Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }.buttonStyle(HTBSecondary()).controlSize(.small)
                                }
                                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                if shown.isEmpty { Text("Nothing set here").font(.caption).foregroundStyle(.tertiary) }
                                else if let d = try? JSONSerialization.data(withJSONObject: shown, options: [.prettyPrinted, .sortedKeys]) {
                                    Text(String(decoding: d, as: UTF8.self)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(16)
                        }
                    }
                }.padding(20)
            }
        }
    }

    private func modePicker(_ c: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permission mode for this session").fontWeight(.semibold)
            ForEach(PermissionMode.allCases.filter { $0 != .bypassPermissions }) { m in
                Button { c.permission = m } label: {
                    HStack {
                        Image(systemName: m.icon).frame(width: 20)
                        VStack(alignment: .leading) { Text(m.label); Text(m.blurb).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if c.permission == m { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }.padding(8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(16)
    }
}

// MARK: Diff (/diff)

struct DiffSheet: View {
    @Environment(Store.self) private var store
    @State private var lines: [String]?

    var body: some View {
        SheetFrame(title: "Uncommitted Changes", width: 820, height: 640) {
            if let lines {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l.isEmpty ? " " : l).font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(color(l)).padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading).background(bg(l))
                        }
                    }.padding(.vertical, 8)
                }.background(.black.opacity(0.25))
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            guard let c = store.current else { return }
            let (out, _) = await Shell.run("git status --short 2>&1; echo; git diff --no-color 2>&1 | head -4000", cwd: c.cwd, timeout: 20)
            lines = out.components(separatedBy: "\n")
        }
    }

    private func color(_ l: String) -> Color {
        if l.hasPrefix("+") && !l.hasPrefix("+++") { return .green }
        if l.hasPrefix("-") && !l.hasPrefix("---") { return .red }
        if l.hasPrefix("@@") { return .cyan }
        if l.hasPrefix("diff ") { return .primary }
        return .secondary
    }
    private func bg(_ l: String) -> Color {
        if l.hasPrefix("+") && !l.hasPrefix("+++") { return .green.opacity(0.12) }
        if l.hasPrefix("-") && !l.hasPrefix("---") { return .red.opacity(0.12) }
        return .clear
    }
}

// MARK: Status (/status)

struct StatusSheet: View {
    @Environment(Store.self) private var store

    var body: some View {
        SheetFrame(title: "Status", width: 560, height: 560) {
            if let c = store.current {
                let cat = store.catalog(c.cwd)
                Form {
                    LabeledContent("Claude Code", value: cat.version.isEmpty ? "—" : cat.version)
                    LabeledContent("Model", value: c.modelName ?? c.model)
                    LabeledContent("Effort", value: c.effort ?? "auto")
                    LabeledContent("Permission mode", value: c.permission.label)
                    LabeledContent("Session", value: c.sessionID ?? "not started yet")
                    LabeledContent("Directory", value: c.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    if let b = c.branch { LabeledContent("Branch", value: b) }
                    if !c.additionalDirs.isEmpty { LabeledContent("Extra folders", value: c.additionalDirs.joined(separator: ", ")) }
                    LabeledContent("Context", value: "\(c.contextTokens / 1000)k / \(c.contextWindow / 1000)k tokens")
                    LabeledContent("Cost", value: String(format: "$%.2f", c.cost))
                    if let u = store.usage {
                        LabeledContent("5-hour usage", value: "\(Int(u.fiveHour * 100))%")
                        LabeledContent("7-day usage", value: "\(Int(u.sevenDay * 100))%")
                    }
                    ForEach(cat.account.sorted(by: { $0.key < $1.key }), id: \.key) { LabeledContent($0.key, value: $0.value) }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
            }
        }
    }
}


// MARK: Project picker (open only what you want)

struct ProjectPicker: View {
    @Environment(Store.self) private var store
    var onDone: () -> Void = {}
    @State private var q = ""

    private var recents: [RecentProject] {
        let f = q.lowercased()
        return store.recentProjects().filter { f.isEmpty || $0.path.lowercased().contains(f) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button { store.pickProject(); onDone() } label: { Label("Choose Folder…", systemImage: "folder.badge.plus").padding(.horizontal, 6) }
                    .buttonStyle(HTBPrimary()).controlSize(.large)
                Text("or drop a folder anywhere on this window").font(.callout).foregroundStyle(.secondary)
            }

            if !store.workspace.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("Open now")
                    ForEach(store.workspace, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent).fontWeight(.medium)
                                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Button { store.closeFolder(path) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Close this project (history stays on disk)")
                        }.padding(12).glassCard(14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                label("From your Claude Code history")
                TextField("Filter folders…", text: $q).textFieldStyle(.roundedBorder)
                if recents.isEmpty {
                    Text(q.isEmpty ? "Every folder with Claude Code history is already open." : "No folders match.").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 6)
                }
                ForEach(recents.prefix(40)) { r in
                    Button { store.openFolder(r.path); onDone() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((r.path as NSString).lastPathComponent).fontWeight(.medium)
                                Text(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Text("\(r.count) session\(r.count == 1 ? "" : "s") · \(relativeTime(r.last))").font(.caption).foregroundStyle(.tertiary)
                        }.padding(12).contentShape(Rectangle())
                    }.buttonStyle(.plain).glassCard(14)
                }
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5, weight: .semibold)).textCase(.uppercase).tracking(0.7).foregroundStyle(.secondary)
    }
}

struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Projects", width: 640, height: 620) {
            ScrollView { ProjectPicker(onDone: { dismiss() }).padding(20) }
        }
    }
}
