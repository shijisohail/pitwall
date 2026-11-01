import SwiftUI
import AppKit

private enum MD: Identifiable {
    case para(Int, String), heading(Int, Int, String), bullet(Int, Int, String, String)
    case code(Int, String, String), quote(Int, String), rule(Int), table(Int, MarkdownTable)

    var id: Int {
        switch self {
        case .para(let i, _), .heading(let i, _, _), .bullet(let i, _, _, _),
             .code(let i, _, _), .quote(let i, _), .rule(let i), .table(let i, _): i
        }
    }
}

private func parse(_ text: String) -> [MD] {
    var out: [MD] = []
    var para: [String] = [], tbl: [String] = []
    var code: [String]? = nil
    var lang = ""
    func flush() {
        if !para.isEmpty { out.append(.para(out.count, para.joined(separator: "\n"))); para = [] }
        if !tbl.isEmpty {
            // A real table renders as a grid; anything pipe-shaped that isn't one stays as plain monospaced text.
            if let t = MarkdownTable.parse(tbl) { out.append(.table(out.count, t)) }
            else { out.append(.code(out.count, "", tbl.joined(separator: "\n"))) }
            tbl = []
        }
    }
    for line in text.components(separatedBy: "\n") {
        if code != nil {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                out.append(.code(out.count, lang, code!.joined(separator: "\n"))); code = nil
            } else { code!.append(line) }
            continue
        }
        let t = line.trimmingCharacters(in: .whitespaces)
        let indent = line.prefix { $0 == " " }.count / 2
        if t.hasPrefix("```") {
            flush(); lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces); code = []
        } else if t.isEmpty { flush() }
        else if t.hasPrefix("|") { if !para.isEmpty { flush() }; tbl.append(line) }
        else if t.hasPrefix("#") {
            flush()
            let n = t.prefix { $0 == "#" }.count
            out.append(.heading(out.count, min(n, 4), String(t.dropFirst(n)).trimmingCharacters(in: .whitespaces)))
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            flush(); out.append(.bullet(out.count, indent, "•", String(t.dropFirst(2))))
        } else if let r = t.range(of: #"^\d+[.)] "#, options: .regularExpression) {
            flush(); out.append(.bullet(out.count, indent, String(t[r]).trimmingCharacters(in: .whitespaces), String(t[r.upperBound...])))
        } else if t.hasPrefix("> ") { flush(); out.append(.quote(out.count, String(t.dropFirst(2)))) }
        else if t == "---" || t == "***" { flush(); out.append(.rule(out.count)) }
        else { if !tbl.isEmpty { flush() }; para.append(line) }
    }
    if let c = code { out.append(.code(out.count, lang, c.joined(separator: "\n"))) }
    flush()
    return out
}

/// Inline markdown. With a `cwd`, code spans and relative links that name an existing file or folder become clickable.
private func inline(_ s: String, cwd: String? = nil, bases: [String] = []) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let src = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    var a = src
    for run in src.runs {
        if let i = run.inlinePresentationIntent, i.contains(.code) {
            a[run.range].font = .system(size: 13, design: .monospaced)
            a[run.range].backgroundColor = Color.primary.opacity(0.12)
            if let cwd, run.link == nil, let f = FileLinks.resolve(String(src[run.range].characters), cwd: cwd, bases: bases),
               let u = FileLinks.link(for: f) { a[run.range].link = u }
        } else if let cwd, let l = run.link, l.scheme == nil || l.scheme == "file" {
            // [report](reports/a.pdf) or a file: link: only if it points at something that exists.
            let raw = l.scheme == "file" ? l.path : (l.absoluteString.removingPercentEncoding ?? l.absoluteString)
            if let f = FileLinks.resolve(raw, cwd: cwd, bases: bases), let u = FileLinks.link(for: f) { a[run.range].link = u }
            else { a[run.range].link = nil }
        }
    }
    return a
}

/// A run of markdown text. Plain text can be selected, but SwiftUI's selectable `Text` swallows clicks, so a link in it
/// is styled yet dead. Text that contains a link is therefore left non-selectable so the link opens (Copy is in its menu).
private struct MDText: View {
    let source: String
    var cwd: String?
    var bases: [String] = []
    var font: Font?
    var color: Color?

    var body: some View {
        let a = inline(source, cwd: cwd, bases: bases)
        let t = Text(a).font(font).foregroundStyle(color ?? .primary).lineSpacing(3)
        if a.runs.contains(where: { $0.link != nil }) {
            t.contextMenu {
                Button("Copy Text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(a.characters), forType: .string) }
            }
        } else {
            t.textSelection(.enabled)
        }
    }
}

struct MarkdownView: View {
    let text: String
    /// The session's folder, so file names in the text can be opened. Nil where there isn't one.
    var cwd: String?

    var body: some View {
        let bases = cwd == nil ? [] : FileLinks.mentionedDirectories(in: text, cwd: cwd)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parse(text)) { block in
                switch block {
                case .para(_, let s):
                    MDText(source: s, cwd: cwd, bases: bases)
                case .heading(_, let n, let s):
                    MDText(source: s, cwd: cwd, bases: bases, font: .system(size: [0, 22, 19, 16, 15][n], weight: .semibold)).padding(.top, 4)
                case .bullet(_, let indent, let marker, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                        MDText(source: s, cwd: cwd, bases: bases)
                    }.padding(.leading, CGFloat(indent) * 18)
                case .quote(_, let s):
                    MDText(source: s, cwd: cwd, bases: bases, color: .secondary).padding(.leading, 12)
                        .overlay(alignment: .leading) { Capsule().fill(.secondary.opacity(0.5)).frame(width: 3) }
                case .rule:
                    Divider()
                case .code(_, let lang, let s):
                    CodeBlock(lang: lang, code: s).textSelection(.enabled)
                case .table(_, let t):
                    TableView(table: t).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lays table cells (row-major, `columns` per row) out in columns sized by `MarkdownTable.fit` for the width it is
/// actually offered, so long cells wrap instead of overflowing, and every cell in a row is as tall as the tallest.
private struct TableLayout: Layout {
    let columns: Int
    let natural: [CGFloat]

    private func widths(_ proposal: ProposedViewSize) -> [CGFloat] {
        MarkdownTable.fit(natural: natural, avail: proposal.width ?? .infinity)
    }
    private func rowHeights(_ subviews: Subviews, _ w: [CGFloat]) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            (0..<columns).map { c in
                subviews[start + c].sizeThatFits(ProposedViewSize(width: w[c], height: nil)).height
            }.max() ?? 0
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = widths(proposal)
        return CGSize(width: w.reduce(0, +), height: rowHeights(subviews, w).reduce(0, +))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(ProposedViewSize(width: bounds.width, height: nil))
        let h = rowHeights(subviews, w)
        var y = bounds.minY
        for (r, rowH) in h.enumerated() {
            var x = bounds.minX
            for c in 0..<columns {
                subviews[r * columns + c].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                                proposal: ProposedViewSize(width: w[c], height: rowH))
                x += w[c]
            }
            y += rowH
        }
    }
}

/// A pipe table drawn as a grid: bold header, per-column alignment, wrapping cells, faint zebra rows.
struct TableView: View {
    let table: MarkdownTable
    private let padX: CGFloat = 12, padY: CGFloat = 7

    private func frameAlign(_ a: MarkdownTable.Align) -> Alignment {
        switch a { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    private func textAlign(_ a: MarkdownTable.Align) -> TextAlignment {
        switch a { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }

    /// Single-line width of `text` as it will be drawn (markdown markers removed, a little slack for code spans).
    private func measure(_ text: String, bold: Bool) -> CGFloat {
        let plain = String(inline(text).characters)
        let font = NSFont.systemFont(ofSize: 13.5, weight: bold ? .semibold : .regular)
        return ceil((plain as NSString).size(withAttributes: [.font: font]).width * 1.04) + 4
    }

    private var natural: [CGFloat] {
        table.header.indices.map { c in
            ([measure(table.header[c], bold: true)] + table.rows.map { measure($0[c], bold: false) }).max()! + padX * 2
        }
    }

    private func cell(_ text: String, col: Int, header: Bool, row: Int) -> some View {
        Text(inline(text)).font(.system(size: 13.5, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Color.primary : Color.primary.opacity(0.92))
            .multilineTextAlignment(textAlign(table.aligns[col]))
            .frame(maxWidth: .infinity, alignment: frameAlign(table.aligns[col]))
            .padding(.horizontal, padX).padding(.vertical, padY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(header ? Color.white.opacity(0.08) : (row.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.035)))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(header ? 0.18 : 0.07)).frame(height: 1) }
    }

    var body: some View {
        let n = table.header.count
        TableLayout(columns: n, natural: natural) {
            ForEach(0..<n, id: \.self) { c in cell(table.header[c], col: c, header: true, row: 0) }
            ForEach(0..<table.rows.count, id: \.self) { r in
                ForEach(0..<n, id: \.self) { c in cell(table.rows[r][c], col: c, header: false, row: r) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }
}

struct CodeBlock: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.18))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12.5, design: .monospaced)).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
    }
}
