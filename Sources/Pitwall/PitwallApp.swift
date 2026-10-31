import SwiftUI

@main
struct PitwallApp: App {
    @State private var store = Store.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(HTB.green)
                .containerBackground(HTB.bg, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1340, height: 840)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Pitwall") { AppInfo.showAbout() } }
            CommandGroup(replacing: .newItem) {
                Button("New Session") { store.newConversation() }.keyboardShortcut("n")
                Button("New Tab") { store.newConversation() }.keyboardShortcut("t")
                Button("Open Project…") { store.pickProject() }.keyboardShortcut("o")
                Divider()
                Button("Pit Wall") { store.showBoard = true }.keyboardShortcut("1")
                Button("Sessions") {
                    if store.current == nil { store.selection = store.filtered.first?.id }
                    store.showBoard = false
                }.keyboardShortcut("2")
                Button("Search All Sessions…") { store.sheet = .switcher }.keyboardShortcut("k")
                Button("Open in Terminal") { store.current?.openInTerminal() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Stop Response") { store.current?.stop() }.keyboardShortcut(".")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { store.closeCurrentTab() }.keyboardShortcut("w")
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { store.cycleTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { store.cycleTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Tab (Control-Tab)") { store.cycleTab(1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab (Control-Shift-Tab)") { store.cycleTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppInfo.diagnostics(store: store), forType: .string)
                }
                if let url = AppInfo.repoURL {
                    Link("Pitwall on GitHub", destination: url)
                    Link("Report an Issue", destination: url.appending(path: "issues/new/choose"))
                }
            }
        }
        Settings { SettingsView().environment(store) }
    }
}
