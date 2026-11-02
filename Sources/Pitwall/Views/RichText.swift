import SwiftUI
import AppKit

/// SwiftUI's `Text` can only select inside one `Text`, so a reply made of paragraphs and bullets could be selected one
/// paragraph at a time and no further. A run of consecutive paragraphs, headings, bullets and quotes is therefore drawn by
/// one native text view: drag across lines and paragraphs, double-click a word, ⌘A, ⌘C, and links stay clickable.
/// Code blocks and tables keep their own views (and their own Copy buttons).
enum RichText {
    /// One attributed string for `items`. Paragraphs are separated by a blank line (so a copy pastes cleanly) drawn as a
    /// thin gap; consecutive bullets are not.
    static func build(_ items: [MD], size: CGFloat, cwd: String?, bases: [String]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: size)
        var previousWasBullet = false

        func piece(_ source: String, font: NSFont, color: NSColor, style: NSParagraphStyle) {
            let a = NSMutableAttributedString(attributedString: ns(inline(source, cwd: cwd, bases: bases), font: font, color: color))
            a.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
            a.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: a.length))
            out.append(a)
        }
        func style(head: CGFloat = 0, first: CGFloat? = nil, tab: CGFloat? = nil) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 3; p.headIndent = head; p.firstLineHeadIndent = first ?? head
            if let tab { p.tabStops = [NSTextTab(textAlignment: .left, location: tab)]; p.defaultTabInterval = tab }
            return p
        }

        for (n, item) in items.enumerated() {
            var isBullet = false
            if case .bullet = item { isBullet = true }
            if n > 0, !(isBullet && previousWasBullet) {
                out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)]))    // the gap between blocks
            }
            previousWasBullet = isBullet

            switch item {
            case .para(_, let s):
                piece(s, font: body, color: .labelColor, style: style())
            case .heading(_, let level, let s):
                let pts: [CGFloat] = [0, 22, 19, 16, 15]
                piece(s, font: NSFont.systemFont(ofSize: pts[min(max(level, 1), 4)], weight: .semibold), color: .labelColor, style: style())
            case .bullet(_, let indent, let marker, let s):
                let x = CGFloat(indent) * 18
                // The marker sits in the hanging indent, so wrapped lines align under the text, not under the bullet.
                let m = NSMutableAttributedString(string: marker + "\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
                m.append(ns(inline(s, cwd: cwd, bases: bases), font: body, color: .labelColor))
                m.append(NSAttributedString(string: "\n", attributes: [.font: body]))
                m.addAttribute(.paragraphStyle, value: style(head: x + 22, first: x + 4, tab: x + 22), range: NSRange(location: 0, length: m.length))
                out.append(m)
            case .quote(_, let s):
                piece(s, font: body, color: .secondaryLabelColor, style: style(head: 14, first: 14))
            default: break          // code, tables and rules are never part of a text run (see MDRun)
            }
        }
        if out.length > 0, out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    /// SwiftUI-flavoured inline markdown → AppKit attributes: bold, italic, code, strikethrough and links.
    static func ns(_ a: AttributedString, font base: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in a.runs {
            var font = base
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                font = NSFont.monospacedSystemFont(ofSize: max(base.pointSize - 1.5, 9), weight: .regular)
                attrs[.backgroundColor] = NSColor.white.withAlphaComponent(0.12)
            }
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }
            attrs[.font] = font
            out.append(NSAttributedString(string: String(a[run.range].characters), attributes: attrs))
        }
        return out
    }

    /// The reply as plain text, the way selecting it all would copy it: no markdown symbols, a blank line between paragraphs.
    static func plainText(_ markdown: String) -> String {
        var out = ""
        var previousWasBullet = false
        for item in parse(markdown) {
            var s = "", bullet = false
            switch item {
            case .para(_, let t), .heading(_, _, let t), .quote(_, let t): s = String(inline(t).characters)
            case .bullet(_, let indent, let marker, let t):
                s = String(repeating: "  ", count: indent) + marker + " " + String(inline(t).characters); bullet = true
            case .code(_, _, let c): s = c
            case .rule: s = "---"
            case .table(_, let t): s = ([t.header] + t.rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
            if !out.isEmpty { out += (bullet && previousWasBullet) ? "\n" : "\n\n" }
            out += s; previousWasBullet = bullet
        }
        return out
    }
}

/// Consecutive text-like blocks form one selectable run; code blocks, tables and rules stand on their own.
enum MDRun: Identifiable {
    case text(Int, [MD]), code(Int, String, String), table(Int, MarkdownTable), rule(Int)

    var id: Int {
        switch self { case .text(let i, _), .code(let i, _, _), .table(let i, _), .rule(let i): i }
    }

    static func group(_ blocks: [MD]) -> [MDRun] {
        var runs: [MDRun] = [], pending: [MD] = []
        func flush() { if let first = pending.first { runs.append(.text(first.id, pending)); pending = [] } }
        for b in blocks {
            switch b {
            case .para, .heading, .bullet, .quote: pending.append(b)
            case .code(let i, let lang, let s): flush(); runs.append(.code(i, lang, s))
            case .table(let i, let t): flush(); runs.append(.table(i, t))
            case .rule(let i): flush(); runs.append(.rule(i))
            }
        }
        flush()
        return runs
    }
}

// MARK: The text view

final class SelectableTextView: NSTextView {
    static func make() -> SelectableTextView {
        let storage = NSTextStorage(), layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; container.widthTracksTextView = true
        layout.addTextContainer(container)
        let v = SelectableTextView(frame: .zero, textContainer: container)     // TextKit 1, so measuring is predictable
        v.isEditable = false; v.isSelectable = true; v.drawsBackground = false
        v.textContainerInset = .zero; v.isVerticallyResizable = false; v.isHorizontallyResizable = false
        v.isAutomaticLinkDetectionEnabled = false
        v.linkTextAttributes = [.foregroundColor: NSColor(HTB.cyan), .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        return v
    }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
}

struct RichTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    let onLink: (URL) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onLink: (URL) -> Void
        init(_ onLink: @escaping (URL) -> Void) { self.onLink = onLink }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            onLink(url); return true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onLink) }

    func makeNSView(context: Context) -> SelectableTextView {
        let v = SelectableTextView.make()
        v.delegate = context.coordinator
        v.textStorage?.setAttributedString(attributed)
        return v
    }

    func updateNSView(_ v: SelectableTextView, context: Context) {
        context.coordinator.onLink = onLink
        guard let storage = v.textStorage, !storage.isEqual(to: attributed) else { return }      // unchanged: keep the selection
        let selection = v.selectedRange()
        storage.setAttributedString(attributed)
        if NSMaxRange(selection) <= storage.length { v.setSelectedRange(selection) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: SelectableTextView, context: Context) -> CGSize? {
        guard let container = v.textContainer, let layout = v.layoutManager else { return nil }
        let width = max(min(proposal.width ?? 600, 10_000), 20)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}
