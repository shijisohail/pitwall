import Testing
import AppKit
@testable import Pitwall

@MainActor @Suite struct RichTextTests {
    private let sample = """
    Hi Sam,

    Email is **blocked** by `ufw`. See [the runbook](https://example.com/runbook).

    - `SMTP_PORT` is 465
    - second bullet

    1. first step
    2. second step

    ```sh
    echo hi
    ```

    | a | b |
    |---|---|
    | 1 | 2 |

    Thanks,
    Sharjeel
    """

    private func textItems(_ md: String) -> [MD] {
        MDRun.group(parse(md)).flatMap { run -> [MD] in if case .text(_, let items) = run { items } else { [] } }
    }

    @Test func plainTextIsWhatSelectingItAllWouldCopy() {
        let t = RichText.plainText(sample)
        #expect(!t.contains("**") && !t.contains("`") && !t.contains("]("))               // no markdown symbols
        #expect(t.hasPrefix("Hi Sam,\n\nEmail is blocked by ufw. See the runbook."))        // blank line between paragraphs
        #expect(t.contains("• SMTP_PORT is 465\n• second bullet"))                          // bullets stay on consecutive lines
        #expect(t.contains("1. first step\n2. second step"))
        #expect(t.contains("echo hi") && t.contains("a\tb\n1\t2"))                          // code verbatim, table as tab-separated rows
        #expect(t.hasSuffix("Thanks,\nSharjeel"))                                           // a soft line break inside a paragraph is kept
    }

    @Test func textRunsStopAtCodeBlocksAndTables() {
        let kinds = MDRun.group(parse(sample)).map { r -> String in
            switch r { case .text(_, let i): "text\(i.count)"; case .code: "code"; case .table: "table"; case .rule: "rule" }
        }
        #expect(kinds == ["text6", "code", "table", "text1"])      // paragraph, paragraph, 2 bullets, 2 numbered | code | table | paragraph
        #expect(Set(MDRun.group(parse(sample)).map(\.id)).count == 4)
    }

    @Test func oneAttributedStringKeepsBlankLinesAndTightBullets() {
        let a = RichText.build(textItems(sample), size: 13, cwd: nil, bases: [])
        let s = a.string
        #expect(s.hasPrefix("Hi Sam,\n\nEmail is blocked"))
        #expect(s.contains("•\tSMTP_PORT is 465\n•\tsecond bullet\n1.\tfirst step\n2.\tsecond step\n\n"))     // no gap between list items, one after the list
        #expect(!s.hasSuffix("\n") || s.hasSuffix("Sharjeel"))
        #expect(!s.contains("**") && !s.contains("`"))
    }

    @Test func inlineFormattingSurvivesTheConversion() {
        let a = RichText.build(textItems(sample), size: 13, cwd: nil, bases: [])
        let s = a.string as NSString
        let bold = a.attribute(.font, at: s.range(of: "blocked").location, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let code = s.range(of: "ufw").location
        #expect(a.attribute(.backgroundColor, at: code, effectiveRange: nil) != nil)
        #expect((a.attribute(.font, at: code, effectiveRange: nil) as? NSFont)?.isFixedPitch == true)
        let link = a.attribute(.link, at: s.range(of: "the runbook").location, effectiveRange: nil) as? URL
        #expect(link?.host == "example.com")
    }

    @Test func aBulletsWrappedLinesHangUnderTheText() {
        let a = RichText.build(textItems("- one"), size: 13, cwd: nil, bases: [])
        let p = a.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((p?.headIndent ?? 0) > (p?.firstLineHeadIndent ?? 0))
    }

    @Test func selectingAcrossParagraphsCopiesTheWholeRange() {
        let a = RichText.build(textItems(sample), size: 13, cwd: nil, bases: [])
        let v = SelectableTextView.make()
        v.textStorage?.setAttributedString(a)
        v.selectAll(nil)
        #expect(v.attributedSubstring(forProposedRange: v.selectedRange(), actualRange: nil)?.string == a.string)
        let s = a.string as NSString
        let start = s.range(of: "blocked").location, end = s.range(of: "second bullet").location
        v.setSelectedRange(NSRange(location: start, length: end - start))                  // from one paragraph into a later bullet
        let part = v.attributedSubstring(forProposedRange: v.selectedRange(), actualRange: nil)?.string ?? ""
        #expect(part.hasPrefix("blocked by ufw") && part.contains("SMTP_PORT") && part.contains("\n\n"))
    }

    @Test func clickingALinkHandsItToTheCaller() {
        var opened: URL?
        let coordinator = RichTextView(attributed: NSAttributedString(string: "x"), onLink: { opened = $0 }).makeCoordinator()
        let v = SelectableTextView.make()
        #expect(coordinator.textView(v, clickedOnLink: URL(string: "https://example.com/x")!, at: 0))
        #expect(opened?.absoluteString == "https://example.com/x")
        #expect(coordinator.textView(v, clickedOnLink: "https://example.org", at: 0) && opened?.host == "example.org")     // a String link works too
        #expect(!coordinator.textView(v, clickedOnLink: 42, at: 0))
    }

    @Test func aReplysMarkdownJoinsItsTextBlocksOnly() {
        var m = ChatMessage(role: .assistant)
        m.blocks = [Block(kind: .text, text: "one"), Block(kind: .tool, toolName: "Bash"), Block(kind: .text, text: "two"), Block(kind: .text, text: "")]
        #expect(m.replyMarkdown == "one\n\ntwo")
        #expect(ChatMessage(role: .assistant, blocks: [Block(kind: .tool)]).replyMarkdown == nil)
    }
}
