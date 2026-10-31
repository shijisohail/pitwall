import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminalApp.cleanupHandoffFiles()
    }

    /// Folders dropped on the Dock icon, or opened with "Open With", become opened projects.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            Store.shared.openFolder(url.path)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = Store.shared
        let running = store.conversations.filter(\.isRunning)
        if !running.isEmpty, AppSettings.shared.confirmQuitWhileRunning {
            let a = NSAlert()
            a.messageText = "Quit Pitwall?"
            a.informativeText = "\(running.count) session\(running.count == 1 ? " is" : "s are") still working and will be stopped. Their history is kept, and you can resume them later."
            a.addButton(withTitle: "Quit"); a.addButton(withTitle: "Cancel")
            if a.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        store.conversations.forEach { $0.runner?.stop() }     // don't leave `claude` children running after quit
        return .terminateNow
    }
}
