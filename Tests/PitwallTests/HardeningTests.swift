import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite struct HardeningTests {
    @Test func onlyWebAndMailLinksMayOpen() {
        for ok in ["http://example.com", "https://example.com/a?b=c", "HTTPS://EXAMPLE.COM", "mailto:a@b.c"] {
            #expect(LinkPolicy.allows(URL(string: ok)!), "\(ok)")
        }
        for bad in ["file:///Applications/Calculator.app", "x-apple.systempreferences:com.apple.preference.security", "javascript:alert(1)",
                    "ssh://host", "someapp://do-thing", "tel:123", "/just/a/path"] {
            #expect(!LinkPolicy.allows(URL(string: bad)!), "\(bad)")
        }
    }

    @Test func clipKeepsSmallOutputAndBoundsHugeOutput() {
        #expect(Limits.clip("short") == "short")
        let big = String(repeating: "y", count: 250_000)
        let clipped = Limits.clip(big)
        #expect(clipped.count < Limits.toolResult + 100)
        #expect(clipped.hasSuffix("more characters]")); #expect(clipped.contains("150000"))
    }

    @Test func handoffCleanupRemovesOnlyStaleCommandFiles() throws {
        try withTempDir { dir in
            let old = dir.appendingPathComponent("old.command"), fresh = dir.appendingPathComponent("fresh.command"), other = dir.appendingPathComponent("keep.txt")
            for f in [old, fresh, other] { try "x".write(to: f, atomically: true, encoding: .utf8) }
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: old.path)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: other.path)
            TerminalApp.cleanupHandoffFiles(in: dir)
            #expect(!FileManager.default.fileExists(atPath: old.path))
            #expect(FileManager.default.fileExists(atPath: fresh.path))
            #expect(FileManager.default.fileExists(atPath: other.path))      // never touches files it didn't create
        }
    }

    @Test func settingsHaveSafeDefaultsAndFullAccessIsNeverTheDefault() {
        let fresh = AppSettings(defaults: UserDefaults(suiteName: "pitwall-tests-\(UUID().uuidString)")!)
        #expect(fresh.defaultPermission == .acceptEdits); #expect(!fresh.animatedBackground); #expect(fresh.confirmQuitWhileRunning)
        #expect(fresh.claudePath.isEmpty)

        let d = UserDefaults(suiteName: "pitwall-tests-\(UUID().uuidString)")!
        d.set("bypassPermissions", forKey: "defaultPermission")          // e.g. tampered preferences
        #expect(AppSettings(defaults: d).defaultPermission == .acceptEdits)
        d.set("plan", forKey: "defaultPermission")
        #expect(AppSettings(defaults: d).defaultPermission == .plan)
    }

    @Test func diagnosticsNeverLeakPathsTitlesOrContent() {
        let s = makeStore()
        s.workspace = ["/Users/secret/project"]
        let c = Conversation(cwd: "/Users/secret/project"); c.title = "very secret title"; c.store = s
        c.messages = [ChatMessage(role: .user, blocks: [Block(kind: .text, text: "my password is hunter2")])]
        s.conversations.append(c)
        let d = AppInfo.diagnostics(store: s)
        #expect(d.contains("Pitwall")); #expect(d.contains("macOS")); #expect(d.contains("opened folders: 1"))
        for leak in ["secret", "hunter2", "/Users"] { #expect(!d.contains(leak), "leaked \(leak)") }
    }
}
