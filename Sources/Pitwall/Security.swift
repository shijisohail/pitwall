import Foundation

/// Model output is untrusted: a link in it must not be able to launch an app (`file:`), open a system pane
/// or invoke another app's URL scheme. Only web and mail links are allowed to open.
enum LinkPolicy {
    static func allows(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}
