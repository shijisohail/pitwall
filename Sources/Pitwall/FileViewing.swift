import Foundation
import UniformTypeIdentifiers

/// How a file opens inside Pitwall. Viewing is read-only and never runs anything.
enum ViewerKind: Equatable {
    case markdown, text, json, image, pdf
    case quickLook          // anything macOS can preview (Office documents, audio, video, ...)
    case folder             // shown in Finder
    case reveal             // apps, installers and executables: shown in Finder, never opened
    case missing
}

enum FileViewing {
    /// Larger files are cut off; the viewer says so and offers the default app.
    static let maxTextBytes = 2_000_000
    /// Lines shown at once. Selecting across a very long file would stall the window, so it stops here.
    static let maxLines = 5_000

    static let markdownExts: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico", "icns", "svg"]
    /// Real binaries and bundles: never previewed or launched from here. (A script is just text, and viewing it runs nothing.)
    static let revealExts: Set<String> = ["app", "pkg", "mpkg", "dmg", "jar", "exe", "msi", "workflow", "action", "osax", "scptd", "terminal", "tool"]

    static func kind(for url: URL) -> ViewerKind {
        let u = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { return .missing }
        let ext = u.pathExtension.lowercased()
        if isDir.boolValue { return revealExts.contains(ext) ? .reveal : .folder }
        if revealExts.contains(ext) { return .reveal }
        if markdownExts.contains(ext) { return .markdown }
        if ext == "json" { return .json }
        if imageExts.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if looksLikeText(u) { return .text }
        // Unknown binary: an executable is never opened, anything else gets the system preview.
        return FileManager.default.isExecutableFile(atPath: u.path) ? .reveal : .quickLook
    }

    /// Text if the first few KB have no NUL byte and are not obviously binary.
    static func looksLikeText(_ url: URL) -> Bool {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 4096)) ?? Data()          // nil at end of file: an empty file is empty text
        if head.isEmpty { return true }
        if head.contains(0) { return false }
        // Count bytes that are neither printable nor whitespace; a little is fine (UTF-8, ANSI), a lot is binary.
        let odd = head.filter { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && $0 != 0x1B && $0 != 0x0C }.count
        return odd * 20 < head.count
    }

    struct Text: Equatable {
        var text: String
        var totalBytes: Int
        var truncatedBytes: Bool      // the file is larger than maxTextBytes
        var truncatedLines: Bool      // there are more than maxLines lines
        var lineCount: Int
    }

    /// The beginning of a text file, safe to show: capped in bytes and in lines.
    static func loadText(_ url: URL) -> Text? {
        let u = url.resolvingSymlinksInPath()
        guard let h = FileHandle(forReadingAtPath: u.path) else { return nil }
        defer { try? h.close() }
        let size = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int) ?? 0
        let data = (try? h.read(upToCount: maxTextBytes)) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cutLines = lines.count > maxLines
        if cutLines { lines = Array(lines.prefix(maxLines)); text = lines.joined(separator: "\n") }
        return Text(text: text, totalBytes: size, truncatedBytes: size > maxTextBytes, truncatedLines: cutLines, lineCount: lines.count)
    }

    /// Indented JSON, or nil if it does not parse (then the viewer shows it as it is).
    static func prettyJSON(_ s: String) -> String? {
        guard let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    static func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
