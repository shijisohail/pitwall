import Testing
import Foundation
@testable import Pitwall

@Suite struct PromptHighlightTests {
    private func known(_ names: Set<String>) -> (String) -> Bool { { n in names.contains { $0.caseInsensitiveCompare(n) == .orderedSame } } }
    private func got(_ s: String, _ isKnown: ((String) -> Bool)? = nil) -> [String] {
        PromptHighlight.spans(in: s, isKnownCommand: isKnown).map { String(s[$0.range]) }
    }

    @Test func magicWordsAreFoundAnywhereAndIgnoreCase() {
        #expect(got("please ultrathink about this") == ["ultrathink"])
        #expect(got("ULTRATHINK now") == ["ULTRATHINK"])
        #expect(got("ultracode and ultrathink") == ["ultracode", "ultrathink"])
        #expect(got("ULTRAPLAN it") == ["ULTRAPLAN"])
        #expect(got("ultrathinking is not it") == [])
        #expect(got("see docs/ultrathink-notes.md") == ["ultrathink"])      // Claude Code's own rule is /\bultrathink\b/i, so it fires here too
    }

    @Test func aSlashCommandCountsOnlyAtTheStartAndOnlyAsABareName() {
        #expect(got("/review") == ["/review"])
        #expect(got("/review the diff") == ["/review"])
        #expect(got("/plugin:thing-x run") == ["/plugin:thing-x"])
        #expect(got("/Users/me/file.txt") == [])
        #expect(got("explain /review") == [])
    }

    @Test func knownCommandsKeepHalfTypedAndUnknownCommandsPlain() {
        let k = known(["review"])
        #expect(got("/rev", k) == [])
        #expect(got("/nope", k) == [])
        #expect(got("/tmp is full", k) == [])
        #expect(got("/review", k) == ["/review"])
        #expect(got("/Review", k) == ["/Review"])
    }

    @Test func mentionsAndShellPrefix() {
        #expect(got("look at @src/App.swift now") == ["@src/App.swift"])
        #expect(got("mail me@x.com") == [])
        #expect(got("!ls -la") == ["!"])
        #expect(got("!") == [])
        #expect(got("hey !ls") == [])
    }

    @Test func spansNeverOverlap() {
        #expect(got("/ultrathink") == ["/ultrathink"])
        #expect(got("@ultrathink.md") == ["@ultrathink.md"])
        #expect(got("use ultrathink on @a.swift") == ["ultrathink", "@a.swift"])
    }

    @Test func nonAsciiTextKeepsItsRanges() {
        #expect(got("héllo ultrathink 😀 @fïle.swift") == ["ultrathink", "@fïle.swift"])
        #expect(got("") == [])
    }

    @Test func renderingNeverChangesTheText() {
        let s = "ultrathink 😀 /review @a !x"
        #expect(String(PromptHighlight.sent(s).characters) == s)
        #expect(PromptHighlight.backdrop("plain prompt", isKnownCommand: nil) == nil)
        #expect(PromptHighlight.backdrop("ultrathink x", isKnownCommand: nil) != nil)
    }
}
