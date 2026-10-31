import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Bindable private var settings = AppSettings.shared
    @State private var confirmForget = false
    @State private var fullDiskAccess = Permissions.hasFullDiskAccess

    private var cliLine: String {
        switch store.cliStatus {
        case .unknown: "Checking…"
        case .ok(let v): v
        case .missing: "Not found"
        }
    }

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Claude Code") {
                HStack {
                    TextField("Path to claude", text: $settings.claudePath, prompt: Text("Auto-detect"))
                    Button("Choose…") {
                        let p = NSOpenPanel(); p.message = "Choose the claude executable"; p.prompt = "Use This"
                        if p.runModal() == .OK, let u = p.url { settings.claudePath = u.path }
                    }
                }
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        Circle().fill(store.cliStatus == .missing ? HTB.red : HTB.green).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(cliLine).font(.system(.body, design: .monospaced))
                        Button("Re-check") { Task { await store.checkCLI() } }
                    }
                }
            }
            Section("New sessions") {
                Picker("Permission mode", selection: $settings.defaultPermission) {
                    ForEach(PermissionMode.allCases.filter { $0 != .bypassPermissions }) { Text($0.label).tag($0) }
                }
                Text(settings.defaultPermission.blurb).font(.caption).foregroundStyle(.secondary)
                Toggle("Confirm before quitting while sessions are working", isOn: $settings.confirmQuitWhileRunning)
            }
            Section("Appearance") {
                Toggle("Animate the background", isOn: $settings.animatedBackground)
                Text("Slowly drifting glows. Uses a few percent of a CPU core while the window is open, and is always off when macOS Reduce Motion is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("History") {
                Toggle("Show sessions started by scripts and the SDK", isOn: $store.showAutomation)
                Button("Forget opened projects…", role: .destructive) { confirmForget = true }
                    .confirmationDialog("Close all opened projects?", isPresented: $confirmForget) {
                        Button("Close All Projects", role: .destructive) {
                            store.conversations.forEach { $0.teardown() }
                            store.workspace = []; store.tabs = []; store.focusProject = nil; store.selection = nil; store.showBoard = true
                        }
                    } message: { Text("Nothing is deleted. Your Claude Code history stays on disk.") }
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    HStack(spacing: 8) {
                        Circle().fill(fullDiskAccess ? HTB.green : Color.secondary.opacity(0.6)).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(fullDiskAccess ? "Granted" : "Not granted")
                    }
                }
                Text("macOS asks separately for Documents, Desktop, Downloads, network volumes and more, the first time Claude Code or a command it runs touches each one. Full Disk Access answers all of those once. It is optional: skip it if you would rather approve folder by folder.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Full Disk Access…") { Permissions.openFullDiskAccess() }
                    Button("Open Files & Folders…") { Permissions.openFilesAndFolders() }
                }
            }
            Section("Privacy") {
                Text("Pitwall has no telemetry and makes no network connections of its own. It reads Claude Code's local history and talks only to the `claude` process it launches.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .preferredColorScheme(.dark)
        .task { if store.cliStatus == .unknown { await store.checkCLI() } }
        // Coming back from System Settings: re-check.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fullDiskAccess = Permissions.hasFullDiskAccess }
    }
}
