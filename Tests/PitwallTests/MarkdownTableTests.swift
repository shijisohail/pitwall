import Testing
import Foundation
@testable import Pitwall

@Suite struct MarkdownTableTests {
    @Test func parsesHeaderAlignmentsAndRows() throws {
        let t = try #require(MarkdownTable.parse(["| Repo | # | Title |", "|---|---:|:--:|", "| a | 1 | x |"]))
        #expect(t.header == ["Repo", "#", "Title"])
        #expect(t.aligns == [.leading, .trailing, .center])
        #expect(t.rows == [["a", "1", "x"]])
    }

    @Test func shortAndLongRowsAreNormalised() throws {
        let t = try #require(MarkdownTable.parse(["| a | b | c |", "|---|---|---|", "| 1 | 2 |", "| 1 | 2 | 3 | 4 |"]))
        #expect(t.rows == [["1", "2", ""], ["1", "2", "3"]])
    }

    @Test func escapedPipesStayInsideTheCell() {
        #expect(MarkdownTable.cells("| a \\| b | c |") == ["a | b", "c"])
        #expect(MarkdownTable.cells("a | b | c") == ["a", "b", "c"])
    }

    @Test func textWithoutASeparatorRowIsNotATable() {
        #expect(MarkdownTable.parse(["| a | b |", "| c | d |"]) == nil)
        #expect(MarkdownTable.parse(["| a | b |", "|---|"]) == nil)
        #expect(MarkdownTable.parse(["| only |"]) == nil)
    }

    @Test func columnWidthsKeepFittingTablesAndCapTheWidestOtherwise() {
        #expect(MarkdownTable.fit(natural: [100, 80], avail: 500) == [100, 80])
        let w = MarkdownTable.fit(natural: [100, 80, 600], avail: 500)
        #expect(w[0] == 100 && w[1] == 80 && abs(w.reduce(0, +) - 500) < 1)
        let tiny = MarkdownTable.fit(natural: [300, 300, 300], avail: 150)
        #expect(abs(tiny.reduce(0, +) - 150) < 1)
    }
}
