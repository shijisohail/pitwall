import SwiftUI
import AppKit

// MARK: Shared bits

extension Store {
    /// Open every dropped folder as a project. Returns false when nothing dropped was a folder.
    @discardableResult
    func openDropped(_ urls: [URL]) -> Bool {
        let dirs = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        dirs.forEach { openFolder($0.path) }
        return !dirs.isEmpty
    }
}

private struct HoverLift: ViewModifier {
    let radius: CGFloat
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(HTB.green.opacity(hover ? 0.6 : 0), lineWidth: 1))
            .shadow(color: HTB.green.opacity(hover ? 0.18 : 0), radius: 14)
            .offset(y: hover && !reduceMotion ? -2 : 0)
            .animation(.easeOut(duration: 0.14), value: hover)
            .onHover { hover = $0 }
    }
}

private extension View {
    func hoverLift(_ radius: CGFloat = 12) -> some View { modifier(HoverLift(radius: radius)) }
}

private func sectionLabel(_ t: String) -> some View {
    Text(t).font(.system(size: 11.5, weight: .bold, design: .monospaced)).textCase(.uppercase).tracking(0.8).foregroundStyle(.secondary)
}

/// Stable accent per project so cards are recognisable at a glance.
private func accent(for name: String) -> Color {
    let palette = [HTB.green, HTB.cyan, HTB.amber, Color(red: 0.75, green: 0.55, blue: 1.0), Color(red: 1.0, green: 0.45, blue: 0.62)]
    return palette[name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
}

private var greeting: String {
    let h = Calendar.current.component(.hour, from: Date())
    let part = h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    if let name = NSFullUserName().split(separator: " ").first { return "\(part), \(name)" }
    return part
}

/// The logo tile with a slow breathing glow behind it.
private struct HeroMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [HTB.green.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 90))
                .frame(width: 180, height: 180)
                .scaleEffect(pulse ? 1.12 : 0.88).opacity(pulse ? 1 : 0.55)
            Image(systemName: "sparkles").font(.system(size: 36, weight: .light)).foregroundStyle(HTB.green)
                .frame(width: 88, height: 88)
                .panel(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: HTB.green.opacity(0.08), border: HTB.green.opacity(0.55))
        }
        .frame(height: 120)
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { pulse = true } } }
        .accessibilityHidden(true)
    }
}

// MARK: Home (the Pit Wall board when nothing is running)

struct HomeView: View {
    let recent: [Conversation]
    @Environment(Store.self) private var store
    @State private var prompt = ""
    @State private var target: String?
    @FocusState private var focused: Bool

    private var targetPath: String? { target ?? store.focusProject ?? store.projects.first?.path }
    private var targetName: String { targetPath.map { ($0 as NSString).lastPathComponent } ?? "Choose project" }

    private let ideas: [(icon: String, title: String, sub: String, prompt: String)] = [
        ("magnifyingglass", "Explain this codebase", "Architecture, modules, entry points", "Give me a tour of this codebase: architecture, key modules and entry points."),
        ("checkmark.seal", "Fix failing tests", "Run the suite, find the cause, patch it", "Run the test suite, find why anything fails, and fix it."),
        ("map", "Plan a feature", "Think first, no edits until you say so", "/plan"),
        ("arrow.triangle.branch", "Review my changes", "Bugs and risks in the uncommitted diff", "Review the uncommitted changes in git and point out bugs, risks and missing tests."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                PermissionsTip()
                tiles
                projects
                if !recent.isEmpty { sessions }
            }
            .frame(maxWidth: 980).frame(maxWidth: .infinity)
            .padding(.top, 14).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .onChange(of: store.focusProject) { target = nil }
        .onAppear { focused = true }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 16) {
            HeroMark()
            Text(greeting).font(.system(size: 30, weight: .semibold))
            Text("What should Claude work on?").font(.system(size: 15)).foregroundStyle(.secondary).offset(y: -8)

            HStack(spacing: 10) {
                Text("❯").font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(HTB.green)
                TextField("Describe a task, ask a question, or type / for commands…", text: $prompt)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($focused).onSubmit { start(prompt) }
                Menu {
                    ForEach(store.projects) { p in Button(p.name) { target = p.path } }
                    if !store.projects.isEmpty { Divider() }
                    Button("Open Project…") { store.sheet = .projects }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "folder"); Text(targetName).lineLimit(1) }
                        .font(.system(size: 12.5)).padding(.horizontal, 11).padding(.vertical, 6)
                        .background(.white.opacity(0.1), in: Capsule()).foregroundStyle(.secondary)
                }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                Button { start(prompt) } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).frame(width: 32, height: 32) }
                    .buttonStyle(HTBPrimary(circle: true)).disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || targetPath == nil)
                    .accessibilityLabel("Start session")
            }
            .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: 720)
            .panel(RoundedRectangle(cornerRadius: 14, style: .continuous), border: HTB.green.opacity(0.4))
            .shadow(color: HTB.green.opacity(0.12), radius: 22)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Quick actions

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            ForEach(ideas, id: \.title) { i in
                Button { start(i.prompt) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: i.icon).font(.system(size: 16)).foregroundStyle(HTB.green)
                            .frame(width: 34, height: 34).background(HTB.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.title).font(.system(size: 14, weight: .semibold))
                            Text(i.sub).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).glassCard(12).hoverLift()
                .disabled(targetPath == nil)
                .help(targetPath == nil ? "Open a project first" : "Starts a new session in \(targetName)")
            }
        }
    }

    // MARK: Projects

    private var projects: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Your projects")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                ForEach(store.projects) { ProjectCard(project: $0) }
                AddProjectCard()
            }
        }
    }

    // MARK: Recent sessions

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Pick up where you left off")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(recent.prefix(6)) { SessionCard(c: $0) }
            }
        }
    }

    private func start(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard let dir = targetPath else { store.sheet = .projects; return }
        store.newConversation(cwd: dir)
        store.current?.send(t)
        prompt = ""
    }
}

// MARK: Project cards

private struct ProjectCard: View {
    let project: Project
    @Environment(Store.self) private var store

    var body: some View {
        let convs = store.conversations(in: project)
        let latest = convs.max { $0.updatedAt < $1.updatedAt }
        let live = convs.filter { $0.isRunning || $0.externallyActive }.count
        let waiting = convs.filter { !$0.approvals.isEmpty }.count
        let tint = accent(for: project.name)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "folder.fill").foregroundStyle(tint).frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(project.shortPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
                Button { store.newConversation(cwd: project.path) } label: { Image(systemName: "plus").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(HTBSecondary(circle: true)).help("New session in \(project.name)").accessibilityLabel("New session in \(project.name)")
            }
            HStack(spacing: 10) {
                if waiting > 0 { badge("\(waiting) need\(waiting == 1 ? "s" : "") you", HTB.amber, pulse: false) }
                if live > 0 { badge("\(live) working", HTB.green, pulse: true) }
                if let b = latest?.branch {
                    Label(b, systemImage: "arrow.triangle.branch").lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(convs.isEmpty ? "no sessions yet" : "\(convs.count) session\(convs.count == 1 ? "" : "s") · \(relativeTime(latest?.updatedAt ?? Date()))")
                    .foregroundStyle(.tertiary).lineLimit(1)
            }
            .font(.system(size: 11.5, design: .monospaced))
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .glassCard(12).hoverLift().contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { if let latest { store.open(latest) } else { store.newConversation(cwd: project.path) } }
        .contextMenu { Button("Close Project") { store.closeFolder(project.path) } }
        .help(latest == nil ? "Start a session" : "Continue “\(latest!.title)”")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(convs.count) sessions")
        .accessibilityAction(named: "Open") { if let latest { store.open(latest) } else { store.newConversation(cwd: project.path) } }
    }

    private func badge(_ t: String, _ c: Color, pulse: Bool) -> some View {
        HStack(spacing: 5) { PulseDot(color: c, pulsing: pulse); Text(t).foregroundStyle(c) }
    }
}

private struct AddProjectCard: View {
    @Environment(Store.self) private var store
    @State private var targeted = false

    var body: some View {
        Button { store.pickProject() } label: {
            VStack(spacing: 8) {
                Image(systemName: targeted ? "tray.and.arrow.down.fill" : "plus.circle").font(.system(size: 24, weight: .light))
                Text(targeted ? "Drop to open" : "Add a project").font(.system(size: 14, weight: .semibold))
                Text("or drop a folder here").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(targeted ? HTB.green : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 112).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HTB.green.opacity(targeted ? 0.09 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(targeted ? HTB.green : HTB.border, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [7, 5])))
        .hoverLift()
        .dropDestination(for: URL.self, action: { urls, _ in store.openDropped(urls) }, isTargeted: { targeted = $0 })
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

// MARK: Welcome (no project open yet)

struct Welcome: View {
    @Environment(Store.self) private var store
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HeroMark()
                Text("Welcome to Pitwall").font(.system(size: 32, weight: .semibold))
                Text("Pitwall only shows and loads the folders you open. Pick one to begin; your other history stays untouched.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460).offset(y: -8)

                dropZone
                PermissionsTip()

                let recents = store.recentProjects()
                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionLabel("From your Claude Code history")
                            Spacer()
                            if recents.count > 6 { Button("Browse all \(recents.count)") { store.sheet = .projects }.buttonStyle(.plain).font(.caption).foregroundStyle(HTB.green) }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                            ForEach(recents.prefix(6)) { recentCard($0) }
                        }
                    }
                    .frame(maxWidth: 820)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "folder.badge.plus").font(.system(size: 30, weight: .light))
                .foregroundStyle(targeted ? HTB.green : Color.secondary)
            Text(targeted ? "Drop to open this project" : "Drop a project folder here").font(.system(size: 16, weight: .semibold))
            Button { store.pickProject() } label: { Label("Choose Folder…", systemImage: "folder").padding(.horizontal, 6) }
                .buttonStyle(HTBPrimary()).controlSize(.large)
        }
        .frame(maxWidth: 560).padding(.vertical, 30).frame(maxWidth: .infinity)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HTB.green.opacity(targeted ? 0.09 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(targeted ? HTB.green : HTB.border, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [8, 6])))
        .dropDestination(for: URL.self, action: { urls, _ in store.openDropped(urls) }, isTargeted: { targeted = $0 })
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private func recentCard(_ r: RecentProject) -> some View {
        let name = (r.path as NSString).lastPathComponent
        let tint = accent(for: name)
        return Button { store.openFolder(r.path) } label: {
            HStack(spacing: 11) {
                Image(systemName: "folder.fill").foregroundStyle(tint).frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(r.count) session\(r.count == 1 ? "" : "s") · \(relativeTime(r.last))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).glassCard(12).hoverLift()
        .help(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }
}

// MARK: One-time tip about macOS folder permissions

/// Shown once, until dismissed or Full Disk Access is on. macOS prompts per folder as Claude Code first touches each one;
/// this explains why and offers a single deliberate alternative.
struct PermissionsTip: View {
    @Bindable private var settings = AppSettings.shared
    @State private var granted = Permissions.hasFullDiskAccess

    var body: some View {
        if !settings.permissionsTipDismissed && !granted {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 18)).foregroundStyle(HTB.cyan).frame(width: 26)
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS may ask for folder access").font(.system(size: 13.5, weight: .semibold))
                    Text("It asks once for each place Claude Code first works in, such as Documents or Downloads. Allow the ones you use, or grant Full Disk Access once to skip the pop-ups. Both are optional.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open Full Disk Access") { Permissions.openFullDiskAccess() }.buttonStyle(HTBSecondary()).controlSize(.small)
                        Button("Not now") { settings.permissionsTipDismissed = true }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.top, 2)
                }
                Spacer(minLength: 0)
                Button { settings.permissionsTipDismissed = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("Don't show this again").accessibilityLabel("Dismiss")
            }
            .padding(14).frame(maxWidth: 820, alignment: .leading).glassCard(12)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in granted = Permissions.hasFullDiskAccess }
        }
    }
}
