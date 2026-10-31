import Foundation
import AppKit
import UniformTypeIdentifiers

/// Model output is untrusted: a link in it must not be able to launch an app (`file:`), open a system pane
/// or invoke another app's URL scheme. Only web and mail links are allowed to open.
enum LinkPolicy {
    static func allows(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}

/// Paths shown in the UI come from model output (tool inputs), so clicking one must never *run* something:
/// apps, scripts and other executables are revealed in Finder instead of opened.
enum FilePolicy {
    private static let launchable: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action", "scpt", "scptd", "applescript", "osax",
        "pkg", "mpkg", "dmg", "jar", "sh", "zsh", "bash", "csh", "ksh", "fish", "inetloc", "webloc", "url", "bat", "exe", "msi",
    ]

    static func isSafeToOpen(_ url: URL) -> Bool {
        let u = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: u.path) else { return false }
        let keys: Set<URLResourceKey> = [.isPackageKey, .contentTypeKey]
        let v = try? u.resourceValues(forKeys: keys)
        if v?.isPackage == true || launchable.contains(u.pathExtension.lowercased()) { return false }
        if FileManager.default.isExecutableFile(atPath: u.path), !(isDirectory(u)) { return false }
        if let t = v?.contentType, [UTType.application, .executable, .unixExecutable, .shellScript].contains(where: { t.conforms(to: $0) }) { return false }
        return true
    }

    private static func isDirectory(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Open a document or folder; reveal anything launchable. Does nothing for a path that doesn't exist.
    @MainActor static func openOrReveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if isSafeToOpen(url) { NSWorkspace.shared.open(url) }
        else if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
