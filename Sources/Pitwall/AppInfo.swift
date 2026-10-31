import AppKit

/// Build and project metadata, read from Info.plist (filled in by Scripts/build.sh).
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }

    /// The project's GitHub URL, or nil while it is still the OWNER placeholder.
    static var repoURL: URL? {
        guard let s = Bundle.main.infoDictionary?["PitwallRepoURL"] as? String, !s.isEmpty, !s.contains("OWNER") else { return nil }
        return URL(string: s)
    }

    @MainActor static func showAbout() {
        let credits = NSAttributedString(
            string: "A native macOS front end for Claude Code.\nIndependent project, not affiliated with or endorsed by Anthropic. \"Claude\" and \"Claude Code\" are trademarks of Anthropic.\nOpen source under the MIT license.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
