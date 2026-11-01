import SwiftUI

/// Words and tokens in a prompt that mean something to Claude Code, picked out so you can see they were recognised:
/// `ultrathink` / `ultracode` anywhere, a `/command` at the very start, `@file` mentions, and a leading `!` (run in a shell).
enum PromptHighlight {
    enum Kind: Equatable { case magicWord, command, mention, shell }
    struct Span: Equatable { let range: Range<String.Index>; let kind: Kind }

    /// Keywords Claude Code reacts to wherever they appear in a message. Add a word here and it is highlighted everywhere.
    /// Claude Code finds `ultrathink` with `/\bultrathink\b/i` (a whole word, any case, even inside a URL), and the
    /// highlight follows the same rule so it never claims more or less than the CLI sees.
    static let magicWords = ["ultrathink", "ultracode", "ultraplan"]

    private static let magicRegex = try! NSRegularExpression(
        pattern: "\\b(?:" + magicWords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b",
        options: [.caseInsensitive])
    /// Only the first token counts, and only a bare `/name`: `/Users/me/file` is a path, not a command.
    private static let commandRegex = try! NSRegularExpression(pattern: #"^/[A-Za-z][A-Za-z0-9_:.\-]*(?=\s|$)"#)
    private static let mentionRegex = try! NSRegularExpression(pattern: #"(?<!\S)@[^\s@]+"#)

    /// The highlighted ranges of `text`, in order and never overlapping.
    /// With `isKnownCommand`, a leading `/word` is only highlighted when it names a real command, so a half-typed or
    /// mistyped command, or a path such as `/tmp`, stays plain and a highlighted one can be trusted. Pass nil to
    /// highlight any bare `/word`.
    static func spans(in text: String, isKnownCommand: ((String) -> Bool)? = nil) -> [Span] {
        guard !text.isEmpty else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        var out: [Span] = []
        func add(_ r: NSRange, _ kind: Kind) {
            guard let range = Range(r, in: text), !out.contains(where: { $0.range.overlaps(range) }) else { return }
            out.append(Span(range: range, kind: kind))
        }

        if let m = commandRegex.firstMatch(in: text, range: full), let r = Range(m.range, in: text) {
            let name = String(text[r].dropFirst())
            if isKnownCommand?(name) ?? true { add(m.range, .command) }
        } else if text.hasPrefix("!"), text.count > 1 {
            add(NSRange(location: 0, length: 1), .shell)
        }
        for m in mentionRegex.matches(in: text, range: full) { add(m.range, .mention) }
        for m in magicRegex.matches(in: text, range: full) { add(m.range, .magicWord) }   // last, so `@ultrathink.md` stays a mention
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: Styles

    private static let violet = Color(red: 0.66, green: 0.50, blue: 1.0)
    private static let rainbow: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 1.0, green: 0.69, blue: 0.0), Color(red: 0.95, green: 0.88, blue: 0.2),
        Color(red: 0.62, green: 0.94, blue: 0.0), Color(red: 0.36, green: 0.70, blue: 1.0), Color(red: 0.66, green: 0.50, blue: 1.0),
    ]

    private static func color(_ kind: Kind) -> Color {
        switch kind { case .magicWord: violet; case .command: HTB.cyan; case .mention: HTB.green; case .shell: HTB.amber }
    }

    /// For text you have already sent: recolour the tokens and make them bold. Magic words get a per-letter rainbow.
    static func sent(_ text: String, isKnownCommand: ((String) -> Bool)? = nil) -> AttributedString {
        var a = AttributedString(text)
        for s in spans(in: text, isKnownCommand: isKnownCommand) {
            guard let r = Range(s.range, in: a) else { continue }
            a[r].font = Font.body.weight(.semibold)
            guard s.kind == .magicWord else { a[r].foregroundColor = color(s.kind); continue }
            var i = r.lowerBound, k = 0
            while i < r.upperBound {
                let next = a.characters.index(after: i)
                a[i..<next].foregroundColor = rainbow[k % rainbow.count]
                i = next; k += 1
            }
        }
        return a
    }

    /// For the live input: the same text, invisible, with only a tinted background on each token. It is drawn *behind* the
    /// real text field, so the field keeps its own text and caret and a slight misalignment can only shift a tint.
    /// Nil when there is nothing to highlight, so an ordinary prompt costs nothing.
    static func backdrop(_ text: String, isKnownCommand: ((String) -> Bool)?) -> AttributedString? {
        let found = spans(in: text, isKnownCommand: isKnownCommand)
        guard !found.isEmpty else { return nil }
        var a = AttributedString(text)
        for s in found {
            guard let r = Range(s.range, in: a) else { continue }
            a[r].backgroundColor = color(s.kind).opacity(s.kind == .mention ? 0.20 : 0.30)
        }
        return a
    }
}
