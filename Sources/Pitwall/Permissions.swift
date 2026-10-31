import Foundation
import AppKit

/// macOS asks, folder by folder, whenever Pitwall or anything it launches (`claude`, `git`, a shell command) first touches
/// Documents, Desktop, Downloads, a network volume and so on. Pitwall can't answer those for you, but it can make them
/// one deliberate choice instead of a trickle of surprise pop-ups.
enum Permissions {
    /// Full Disk Access has no prompt, so the only way to know is to try to read a file macOS protects with it.
    static var hasFullDiskAccess: Bool {
        FileHandle(forReadingAtPath: NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db") != nil
    }

    private static func open(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }
    static func openFullDiskAccess() { open("Privacy_AllFiles") }
    static func openFilesAndFolders() { open("Privacy_FilesAndFolders") }
}
