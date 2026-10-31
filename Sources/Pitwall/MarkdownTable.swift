import Foundation
import CoreGraphics

/// A GitHub-style pipe table: a header row, a `|---|:--:|--:|` separator row, then body rows.
struct MarkdownTable: Equatable {
    enum Align { case leading, center, trailing }
    var header: [String]
    var aligns: [Align]
    var rows: [[String]]

    /// Nil when `lines` isn't a table (no separator row), so the caller can fall back to showing the text as-is.
    static func parse(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }
        let header = cells(lines[0])
        let sep = cells(lines[1])
        guard !header.isEmpty, sep.count == header.count,
              sep.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }) else { return nil }
        let aligns: [Align] = sep.map {
            switch ($0.hasPrefix(":"), $0.hasSuffix(":")) {
            case (true, true): .center
            case (false, true): .trailing
            default: .leading
            }
        }
        let n = header.count
        // Short rows are padded and long ones trimmed, so a half-streamed or sloppy row never breaks the grid.
        let rows = lines.dropFirst(2).map { l -> [String] in
            let c = cells(l)
            return c.count >= n ? Array(c.prefix(n)) : c + Array(repeating: "", count: n - c.count)
        }
        return MarkdownTable(header: header, aligns: aligns, rows: rows)
    }

    /// Splits one row on unescaped pipes, ignoring the outer pipes. `\|` is a literal pipe inside a cell.
    static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|"), !s.hasSuffix("\\|") { s.removeLast() }
        var out: [String] = [], cur = "", escaped = false
        for ch in s {
            if escaped { cur.append(ch == "|" ? "|" : "\\\(ch)"); escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(ch) }
        }
        if escaped { cur.append("\\") }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// Column widths for a container `avail` points wide. Columns keep their natural width when everything fits;
    /// otherwise the widest are capped (a binary search for the largest cap that fits) so long cells wrap instead of
    /// running off the edge. If even `minCol`-wide columns don't fit, all columns are scaled down together.
    static func fit(natural: [CGFloat], avail: CGFloat, minCol: CGFloat = 64) -> [CGFloat] {
        let sum = natural.reduce(0, +)
        guard !natural.isEmpty, avail > 0, sum > avail else { return natural }
        func total(_ cap: CGFloat) -> CGFloat { natural.reduce(0) { $0 + min($1, cap) } }
        var lo = minCol, hi = natural.max() ?? minCol
        if total(lo) > avail { return natural.map { max($0 * avail / sum, 24) } }
        for _ in 0..<24 { let mid = (lo + hi) / 2; if total(mid) <= avail { lo = mid } else { hi = mid } }
        return natural.map { min($0, lo) }
    }
}
