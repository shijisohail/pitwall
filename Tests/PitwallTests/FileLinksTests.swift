import Testing
import Foundation
@testable import Pitwall

@Suite struct FileLinksTests {
    private func project() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pw-links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("reports"), withIntermediateDirectories: true)
        for f in ["reports/Al-Mada-Security-2026-11-01.pdf", "reports/Al-Mada-Security-2026-11-01.html", "README.md"] {
            FileManager.default.createFile(atPath: d.appendingPathComponent(f).path, contents: Data("x".utf8))
        }
        return d
    }

    @Test func relativeFilesAndFoldersResolveAgainstTheSessionFolder() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        #expect(FileLinks.resolve("reports/Al-Mada-Security-2026-11-01.pdf", cwd: d.path)?.lastPathComponent == "Al-Mada-Security-2026-11-01.pdf")
        #expect(FileLinks.resolve("reports/", cwd: d.path)?.lastPathComponent == "reports")
        #expect(FileLinks.resolve("README.md", cwd: d.path) != nil)
        #expect(FileLinks.resolve("./README.md", cwd: d.path) != nil)
    }

    @Test func lineSuffixesAndMentionsStillMeanTheFile() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        #expect(FileLinks.resolve("README.md:42", cwd: d.path) != nil)
        #expect(FileLinks.resolve("README.md:42:7", cwd: d.path) != nil)
        #expect(FileLinks.resolve("README.md#L12", cwd: d.path) != nil)
        #expect(FileLinks.resolve("@README.md", cwd: d.path) != nil)
    }

    @Test func absoluteAndHomePathsWork() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        #expect(FileLinks.resolve(d.appendingPathComponent("README.md").path, cwd: nil) != nil)
        #expect(FileLinks.resolve("~/definitely-not-here-\(UUID().uuidString).txt", cwd: nil) == nil)
    }

    @Test func missingFilesAndCodeAreNeverLinked() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        for s in ["nope.pdf", "reports/missing.pdf", "npm run build", "foo.bar()", "a | b", "$HOME/x", "--flag", "https://example.com/a.pdf",
                  "let x = [1, 2]", "git commit -m \"x\"", "rm -rf /", "", "x.y.z()"] {
            #expect(FileLinks.resolve(s, cwd: d.path) == nil, "\(s)")
        }
        #expect(FileLinks.resolve("README.md", cwd: nil) == nil)       // relative path with no folder to resolve against
    }

    @Test func theLinkRoundTripsToTheAbsolutePath() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try #require(FileLinks.resolve("reports/Al-Mada-Security-2026-11-01.pdf", cwd: d.path))
        let url = try #require(FileLinks.link(for: f))
        #expect(url.scheme == FileLinks.scheme && url.path == f.path)
    }

    @Test func bareNamesResolveInsideAFolderTheReplyMentioned() throws {
        let d = try project(); defer { try? FileManager.default.removeItem(at: d) }
        let name = "Al-Mada-Security-2026-11-01.pdf"
        #expect(FileLinks.resolve(name, cwd: d.path) == nil)                                  // not in the session folder itself
        let text = "Files are in `reports/`:\n\n- `\(name)`\n- `nothing.txt`"
        let dirs = FileLinks.mentionedDirectories(in: text, cwd: d.path)
        #expect(dirs.count == 1 && dirs[0].hasSuffix("/reports"))
        #expect(FileLinks.resolve(name, cwd: d.path, bases: dirs)?.path.hasSuffix("/reports/\(name)") == true)
        #expect(FileLinks.resolve("nothing.txt", cwd: d.path, bases: dirs) == nil)
        #expect(FileLinks.mentionedDirectories(in: "no code spans here", cwd: d.path).isEmpty)
        #expect(FileLinks.mentionedDirectories(in: "see `README.md`", cwd: d.path).isEmpty)       // a file is not a folder
    }
}
