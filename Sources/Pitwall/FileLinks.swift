import Foundation

/// Turns file paths that appear in a reply (usually in `code spans`) into clickable links.
/// A path only becomes a link if it exists, so ordinary code like `foo.bar()` or `npm run build` is never touched.
enum FileLinks {
    /// Our own scheme, so a click is routed to `FilePolicy.openOrReveal` (which never launches apps or scripts).
    static let scheme = "pitwall-file"

    /// Cheap filter before touching the disk: path-shaped, with no shell or code punctuation.
    static func looksLikePath(_ s: String) -> Bool {
        guard (1...400).contains(s.count), !s.contains("\n") else { return false }
        if s.rangeOfCharacter(from: CharacterSet(charactersIn: "$|;&<>*?`\"'(){}[]=,")) != nil { return false }
        if s.hasPrefix("-") || s.hasPrefix("http:") || s.hasPrefix("https:") { return false }
        return s.contains("/") || s.range(of: #"^[^\s/]+\.[A-Za-z0-9]{1,10}$"#, options: .regularExpression) != nil
    }

    /// `src/App.swift:42`, `src/App.swift:42:7` and `src/App.swift#L42` all mean the file.
    static func stripLocation(_ s: String) -> String {
        s.replacingOccurrences(of: #"(:\d+){1,2}$|#L\d+(-L?\d+)?$"#, with: "", options: .regularExpression)
    }

    /// The existing file or folder `text` refers to, relative to `cwd` unless it is absolute or starts with `~`.
    /// A bare name that isn't in `cwd` is also tried inside `bases`: the folders the same reply mentioned
    /// ("Files are in `reports/`:" followed by a list of bare file names).
    static func resolve(_ text: String, cwd: String?, bases: [String] = [], fm: FileManager = .default) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") { t.removeFirst() }                      // @-mentions are written as @path
        t = stripLocation(t)
        guard looksLikePath(t) else { return nil }
        var candidates: [String] = []
        if t.hasPrefix("~") { candidates = [(t as NSString).expandingTildeInPath] }
        else if t.hasPrefix("/") { candidates = [t] }
        else {
            if let cwd, !cwd.isEmpty { candidates.append((cwd as NSString).appendingPathComponent(t)) }
            candidates += bases.map { ($0 as NSString).appendingPathComponent(t) }
        }
        for c in candidates {
            let std = (c as NSString).standardizingPath
            if fm.fileExists(atPath: std) { return URL(fileURLWithPath: std) }
        }
        return nil
    }

    /// Folders named in `code spans` of `text` that exist, in order, for resolving bare file names that follow them.
    static func mentionedDirectories(in text: String, cwd: String?, fm: FileManager = .default) -> [String] {
        guard text.contains("`"), let re = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return [] }
        var dirs: [String] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard dirs.count < 8, let r = Range(m.range(at: 1), in: text),
                  let url = resolve(String(text[r]), cwd: cwd, fm: fm) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, !dirs.contains(url.path) { dirs.append(url.path) }
        }
        return dirs
    }

    /// The link the UI attaches: `pitwall-file:///the/absolute/path`.
    static func link(for file: URL) -> URL? {
        var c = URLComponents(); c.scheme = scheme; c.host = ""; c.path = file.path
        return c.url
    }
}
