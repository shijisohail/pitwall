import SwiftUI
import AppKit

struct Composer: View {
    @Bindable var conversation: Conversation
    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var histIndex: Int?
    @State private var menuIndex = 0
    @State private var dismissedFor: String?
    @State private var files: [String] = []
    @FocusState private var focused: Bool

    private var images: [NSImage] { conversation.draftImages }
    private var catalog: Catalog { store.catalog(conversation.cwd) }
    private var history: [String] { store.promptHistory(for: conversation.cwd) }
    private var canSend: Bool { !(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty) && conversation.loadState != .loading }

    // MARK: Menus

    private var slashQuery: String? {
        guard text.hasPrefix("/"), !text.contains(" "), !text.contains("\n") else { return nil }
        return String(text.dropFirst()).lowercased()
    }

    private var slashItems: [SlashCommand] {
        guard let q = slashQuery else { return [] }
        var byName: [String: SlashCommand] = [:]
        for c in catalog.commands { byName[c.name] = c }
        for c in nativeCommands { byName[c.name] = c }
        let all = byName.values.filter { $0.name.lowercased().contains(q) }
        let (pre, rest) = (all.filter { $0.name.lowercased().hasPrefix(q) }, all.filter { !$0.name.lowercased().hasPrefix(q) })
        let sort: (SlashCommand, SlashCommand) -> Bool = { ($0.native ? 0 : 1, $0.name) < ($1.native ? 0 : 1, $1.name) }
        return Array((pre.sorted(by: sort) + rest.sorted(by: sort)).prefix(8))
    }

    private var mentionQuery: String? {
        guard let r = text.range(of: #"(?:^|\s)@([^\s]*)$"#, options: .regularExpression) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces).dropFirst().lowercased()
    }

    private var mentionItems: [String] {
        guard let q = mentionQuery else { return [] }
        let m = q.isEmpty ? files : files.filter { $0.lowercased().contains(q) }
        return Array(m.sorted { $0.count < $1.count }.prefix(8))
    }

    private var menuCount: Int { dismissedFor == text ? 0 : (slashQuery != nil ? slashItems.count : mentionItems.count) }

    // MARK: Body

    var body: some View {
        VStack(spacing: 10) {
            queueList
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Iterate a snapshot of (offset, image): a cell must never index the live array, which can shrink
                        // (send, queue, remove) between SwiftUI deciding to re-run it and running it.
                        ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                            Image(nsImage: img).resizable().scaledToFill().frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button { if conversation.draftImages.indices.contains(i) { conversation.draftImages.remove(at: i) } } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                    }.buttonStyle(.plain).offset(x: 5, y: -5)
                                }
                        }
                    }.padding(.top, 5)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("❯").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(HTB.green)
            TextField(conversation.isRunning ? "queue a message… it sends when Claude finishes" : "ask claude…   / commands · @ files · ! shell", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 15)).lineLimit(1...9)
                .focused($focused).onSubmit(send)
                .onKeyPress(.return, phases: .down) { p in
                    if p.modifiers.contains(.shift) { text += "\n"; return .handled }
                    if menuCount > 0, !(slashQuery != nil && slashItems[safe: menuIndex]?.name.lowercased() == slashQuery) { acceptMenu(); return .handled }
                    return .ignored
                }
                .onKeyPress(.tab, phases: .down) { p in
                    if p.modifiers.contains(.shift) { cyclePermission(); return .handled }
                    if menuCount > 0 { acceptMenu(); return .handled }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if menuCount > 0 { menuIndex = (menuIndex - 1 + menuCount) % menuCount; return .handled }
                    if text.isEmpty, let last = conversation.queue.last { conversation.editQueued(last.id); return .handled }   // ↑ edits the newest queued message
                    return step(+1)
                }
                .onKeyPress(.downArrow) { if menuCount > 0 { menuIndex = (menuIndex + 1) % menuCount; return .handled }; return step(-1) }
                .onKeyPress(.escape) {
                    if menuCount > 0 { dismissedFor = text; return .handled }
                    if conversation.isRunning { conversation.stop(); return .handled }
                    return .ignored
                }
                .onChange(of: text) { menuIndex = 0; if mentionQuery != nil, files.isEmpty { loadFiles() } }
            }

            HStack(spacing: 8) {
                Button(action: attach) { Image(systemName: "paperclip").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Attach images (or drop them anywhere on the chat)").accessibilityLabel("Attach images")
                modelMenu
                effortMenu
                permissionMenu
                Spacer()
                if conversation.isRunning { Text("esc to stop").font(.caption).foregroundStyle(.tertiary) }
                if conversation.isRunning {
                    Button(action: conversation.stop) { Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30) }
                        .buttonStyle(HTBSecondary(circle: true)).help("Stop (esc). Queued messages return to the input.").accessibilityLabel("Stop")
                }
                Button(action: send) {
                    Image(systemName: conversation.isRunning ? "text.append" : "arrow.up").font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(HTBPrimary(circle: true))
                .disabled(!canSend).help(conversation.isRunning ? "Queue this message" : "Send")
                .accessibilityLabel(conversation.isRunning ? "Queue message" : "Send")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .panel(RoundedRectangle(cornerRadius: 12), border: HTB.green.opacity(0.35))
        .overlay(alignment: .topLeading) { menu.alignmentGuide(.top) { $0[.bottom] + 8 } }
        .onAppear { focused = true }
        .onChange(of: conversation.id) { focused = true }
        .onChange(of: store.composerInsert) { if let s = store.composerInsert { text = s; store.composerInsert = nil; focused = true } }
        .onPasteCommand(of: [.image, .png, .tiff]) { _ in pasteImages() }
        .onChange(of: conversation.draftAppend) { flushDraftAppend() }
    }

    // MARK: Pieces

    @ViewBuilder private var queueList: some View {
        if !conversation.queue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(conversation.isRunning ? "Queued · sent when Claude finishes" : "Queued · paused",
                      systemImage: "clock")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(conversation.queue) { m in
                    HStack(spacing: 8) {
                        if !m.images.isEmpty { Label("\(m.images.count)", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                        Text(m.text.isEmpty ? "(image)" : m.text).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        queueButton("bolt.fill", conversation.isRunning ? "Interrupt and send now" : "Send now") { conversation.sendQueuedNow(m.id) }
                        queueButton("pencil", "Edit in the input") { conversation.editQueued(m.id) }
                        queueButton("xmark", "Remove from queue") { conversation.unqueue(m.id) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func queueButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 11)).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help)
    }

    @ViewBuilder private var menu: some View {
        if menuCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if slashQuery != nil {
                    ForEach(Array(slashItems.enumerated()), id: \.element.id) { i, c in
                        row(i, title: "/" + c.name, hint: c.hint, detail: c.description, badge: c.native ? "Pitwall" : nil)
                    }
                } else {
                    ForEach(Array(mentionItems.enumerated()), id: \.element) { i, f in
                        row(i, title: f, hint: "", detail: "", badge: nil, mono: true)
                    }
                }
            }
            .padding(6).frame(maxWidth: 560, alignment: .leading)
            .panel(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ i: Int, title: String, hint: String, detail: String, badge: String?, mono: Bool = false) -> some View {
        Button { menuIndex = i; acceptMenu() } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold, design: mono ? .monospaced : .default)).lineLimit(1)
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let badge { Text(badge).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(.white.opacity(0.1), in: Capsule()) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
            .background(i == menuIndex ? Color.accentColor.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private var models: [ModelInfo] {
        catalog.models.isEmpty
            ? ["default", "opus", "sonnet", "haiku"].map { ModelInfo(value: $0, name: $0.capitalized, detail: "", supportsEffort: true, levels: ["low", "medium", "high", "xhigh", "max"]) }
            : catalog.models
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $conversation.model) {
                ForEach(models) { m in Text(m.detail.isEmpty ? m.name : "\(m.name) — \(m.detail)").tag(m.value) }
            }.pickerStyle(.inline)
        } label: { chip("sparkles", models.first { $0.value == conversation.model }?.name ?? conversation.model) }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }

    @ViewBuilder private var effortMenu: some View {
        let levels = models.first { $0.value == conversation.model }?.levels ?? []
        if !levels.isEmpty {
            Menu {
                Button("Auto") { conversation.setEffort(nil) }
                ForEach(levels, id: \.self) { l in Button(l.capitalized) { conversation.setEffort(l) } }
            } label: { chip("gauge.with.needle", conversation.effort?.capitalized ?? "Effort") }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
        }
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionMode.allCases) { m in
                Button { choose(m) } label: { Label("\(m.label) — \(m.blurb)", systemImage: m.icon) }
            }
        } label: { chip(conversation.permission.icon, conversation.permission.label) }
        .menuStyle(.button).buttonStyle(.plain).fixedSize().help("Permission mode (⇧Tab to cycle)")
    }

    private func chip(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 6) { Image(systemName: icon); Text(label).lineLimit(1) }
            .font(.system(size: 12.5)).padding(.horizontal, 11).padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule()).foregroundStyle(.secondary)
    }

    // MARK: Actions

    /// ⇧⇥ steps through ask → accept edits → plan, as in Claude Code. Full access is never reached by a shortcut.
    private func cyclePermission() {
        let order: [PermissionMode] = [.manual, .acceptEdits, .plan]
        let i = order.firstIndex(of: conversation.permission) ?? -1
        conversation.permission = order[(i + 1) % order.count]
    }

    private func choose(_ m: PermissionMode) {
        if m == .bypassPermissions {
            let a = NSAlert()
            a.messageText = "Allow Claude to act without asking?"
            a.informativeText = "Full access skips every permission check: Claude can edit any file and run any command in this session."
            a.addButton(withTitle: "Enable Full Access"); a.addButton(withTitle: "Cancel")
            a.buttons.first?.hasDestructiveAction = true
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        conversation.permission = m
    }

    private func acceptMenu() {
        if slashQuery != nil, let c = slashItems[safe: menuIndex] { text = "/" + c.name + " "; histIndex = nil }
        else if let f = mentionItems[safe: menuIndex], let r = text.range(of: #"@[^\s]*$"#, options: .regularExpression) {
            text.replaceSubrange(r, with: "@" + f + " ")
        }
        menuIndex = 0
    }

    private func send() {
        guard canSend else { return }
        if conversation.isRunning {         // Claude is working: line it up for when the turn ends
            if conversation.enqueue(text, images: images) { text = ""; conversation.draftImages = []; histIndex = nil }
            return
        }
        if conversation.send(text, images: images) { text = ""; conversation.draftImages = []; histIndex = nil }
    }

    /// ↑/↓ walk through earlier prompts, only when the field is empty or already showing one.
    private func step(_ dir: Int) -> KeyPress.Result {
        let h = history
        guard !h.isEmpty, text.isEmpty || histIndex != nil, !text.contains("\n") else { return .ignored }
        let next = (histIndex ?? -1) + dir
        if next < 0 { histIndex = nil; text = ""; return .handled }
        guard next < h.count else { return .handled }
        histIndex = next; text = h[next]
        return .handled
    }

    private func attach() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]; p.allowsMultipleSelection = true
        if p.runModal() == .OK { conversation.draftImages += p.urls.compactMap { NSImage(contentsOf: $0) } }
    }

    private func pasteImages() {
        if let imgs = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage] { conversation.draftImages += imgs }
    }

    /// Dropped non-image files arrive as `@path` mentions; append them to the prompt.
    private func flushDraftAppend() {
        let m = conversation.draftAppend
        guard !m.isEmpty else { return }
        conversation.draftAppend = []
        let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
        text += sep + m.joined(separator: " ") + " "
        focused = true
    }

    private func loadFiles() {
        let dir = conversation.cwd
        Task {
            let (out, _) = await Shell.run("git ls-files --cached --others --exclude-standard 2>/dev/null | head -6000 || true", cwd: dir, timeout: 15)
            var list = out.split(separator: "\n").map(String.init)
            if list.isEmpty {
                let (f, _) = await Shell.run("find . -maxdepth 4 -type f -not -path '*/.*' -not -path '*/node_modules/*' | head -3000 | sed 's|^\\./||'", cwd: dir, timeout: 15)
                list = f.split(separator: "\n").map(String.init)
            }
            files = list
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
