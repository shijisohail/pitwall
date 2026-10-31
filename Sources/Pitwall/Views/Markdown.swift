import SwiftUI
import AppKit

private enum MD: Identifiable {
    case para(Int, String), heading(Int, Int, String), bullet(Int, Int, String, String)
    case code(Int, String, String), quote(Int, String), rule(Int)

    var id: Int {
        switch self {
        case .para(let i, _), .heading(let i, _, _), .bullet(let i, _, _, _),
             .code(let i, _, _), .quote(let i, _), .rule(let i): i
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
        if !tbl.isEmpty { out.append(.code(out.count, "", tbl.joined(separator: "\n"))); tbl = [] }
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

private func inline(_ s: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let src = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    var a = src
    for run in src.runs {
        if let i = run.inlinePresentationIntent, i.contains(.code) {
            a[run.range].font = .system(size: 13, design: .monospaced)
            a[run.range].backgroundColor = Color.primary.opacity(0.12)
        }
    }
    return a
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parse(text)) { block in
                switch block {
                case .para(_, let s):
                    Text(inline(s)).lineSpacing(3)
                case .heading(_, let n, let s):
                    Text(inline(s)).font(.system(size: [0, 22, 19, 16, 15][n], weight: .semibold)).padding(.top, 4)
                case .bullet(_, let indent, let marker, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                        Text(inline(s)).lineSpacing(3)
                    }.padding(.leading, CGFloat(indent) * 18)
                case .quote(_, let s):
                    Text(inline(s)).foregroundStyle(.secondary).padding(.leading, 12)
                        .overlay(alignment: .leading) { Capsule().fill(.secondary.opacity(0.5)).frame(width: 3) }
                case .rule:
                    Divider()
                case .code(_, let lang, let s):
                    CodeBlock(lang: lang, code: s)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
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
