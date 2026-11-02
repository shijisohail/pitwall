import SwiftUI
import AppKit
import PDFKit
import Quartz

/// A built-in viewer for the files Claude mentions or changes: Markdown rendered, code and text with line numbers,
/// JSON pretty-printed, images, PDFs, and anything else macOS can preview (Office documents, audio, video).
/// Read-only. Nothing in it is ever executed.
struct FileViewerSheet: View {
    @State var path: String
    @State private var back: [String] = []
    @State private var source = false          // show Markdown / JSON as text instead of rendered
    @State private var loaded: FileViewing.Text?
    @State private var kind: ViewerKind?          // nil until the file has been looked at: a spinner, never "missing"
    @State private var actualSize = false
    @Environment(\.dismiss) private var dismiss

    private var url: URL { URL(fileURLWithPath: path) }
    private var dir: String { (path as NSString).deletingLastPathComponent }
    private var canToggleSource: Bool { kind == .markdown || kind == .json }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(minWidth: 720, idealWidth: 900, maxWidth: .infinity, minHeight: 520, idealHeight: 720, maxHeight: .infinity)
        .background { AuroraBackground() }
        // Links inside a viewed document: another file opens here (with Back); a web link goes to the browser.
        .environment(\.openURL, OpenURLAction { link in
            if link.scheme == FileLinks.scheme { MainActor.assumeIsolated { navigate(to: link.path) }; return .handled }
            if link.scheme == nil, !link.path.isEmpty {
                let rel = URL(fileURLWithPath: link.path, relativeTo: URL(fileURLWithPath: dir, isDirectory: true)).standardizedFileURL.path
                if FileManager.default.fileExists(atPath: rel) { MainActor.assumeIsolated { navigate(to: rel) }; return .handled }
            }
            return LinkPolicy.allows(link) ? .systemAction : .discarded
        })
        .task(id: path) { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if !back.isEmpty {
                Button { path = back.removeLast(); source = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help("Back").accessibilityLabel("Back")
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 12)
            if canToggleSource {
                Picker("", selection: $source) { Text(kind == .json ? "Pretty" : "Preview").tag(false); Text("Source").tag(true) }
                    .pickerStyle(.segmented).frame(width: 150).labelsHidden()
            }
            if kind == .image {
                Picker("", selection: $actualSize) { Text("Fit").tag(false); Text("100%").tag(true) }
                    .pickerStyle(.segmented).frame(width: 110).labelsHidden()
            }
            Button("Open") { FilePolicy.openOrReveal(path) }.buttonStyle(HTBSecondary()).controlSize(.small)
                .help("Open in the default app")
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(HTBSecondary()).controlSize(.small)
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
                .buttonStyle(HTBSecondary()).controlSize(.small)
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var detail: String {
        var parts = [(path as NSString).abbreviatingWithTildeInPath]
        if let l = loaded {
            parts.append(FileViewing.sizeLabel(l.totalBytes))
            parts.append("\(l.lineCount) line\(l.lineCount == 1 ? "" : "s")")
        } else if let s = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int { parts.append(FileViewing.sizeLabel(s)) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch kind {
        case nil:
            loading
        case .markdown?:
            if let l = loaded {
                if source { CodeText(file: l) }
                else {
                    ScrollView { MarkdownView(text: l.text, cwd: dir).padding(28).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity) }
                        .overlay(alignment: .bottom) { truncationBanner(l) }
                }
            } else { loading }
        case .text?:
            if let l = loaded { CodeText(file: l) } else { loading }
        case .json?:
            if let l = loaded {
                if !source, l.totalBytes < 1_000_000, let pretty = FileViewing.prettyJSON(l.text) {
                    CodeText(file: FileViewing.Text(text: pretty, totalBytes: l.totalBytes, truncatedBytes: false, truncatedLines: false,
                                                     lineCount: pretty.split(separator: "\n", omittingEmptySubsequences: false).count))
                } else { CodeText(file: l) }
            } else { loading }
        case .image?: ImagePane(url: url, actualSize: actualSize)
        case .pdf?: PDFPane(url: url)
        case .quickLook?: QuickLookPane(url: url)
        case .folder?, .reveal?, .missing?: unavailable
        }
    }

    private var loading: some View { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: kind == .missing ? "questionmark.folder" : "app.dashed").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(kind == .missing ? "This file no longer exists." : "This kind of file isn't previewed here.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Text("Pitwall never opens apps, installers or executables from a preview. Use Reveal to see it in Finder.")
                .font(.system(size: 12)).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func truncationBanner(_ l: FileViewing.Text) -> some View {
        if l.truncatedBytes || l.truncatedLines {
            Text("Showing the beginning of a large file. Use Open for the rest.")
                .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(HTB.amber.opacity(0.18), in: Capsule()).padding(.bottom, 10)
        }
    }

    // MARK: Loading and navigation

    private func navigate(to new: String) {
        guard new != path else { return }
        back.append(path); path = new; source = false
    }

    private func load() async {
        let u = url
        loaded = nil; kind = nil
        let k = await Task.detached { FileViewing.kind(for: u) }.value
        kind = k
        if k == .folder || k == .reveal { FilePolicy.openOrReveal(u.path); dismiss(); return }     // Finder is the right viewer
        guard k == .markdown || k == .text || k == .json else { return }
        loaded = await Task.detached { FileViewing.loadText(u) }.value
        if loaded == nil { kind = .missing }
    }
}

// MARK: Panes

/// Text or code with line numbers. One selectable `Text` (so selection works across lines) beside a column of numbers.
struct CodeText: View {
    let file: FileViewing.Text

    var body: some View {
        let gutter = String(file.lineCount).count
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 14) {
                Text((1...max(file.lineCount, 1)).map(String.init).joined(separator: "\n"))
                    .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
                    .frame(minWidth: CGFloat(gutter) * 8, alignment: .trailing)
                Text(file.text.isEmpty ? " " : file.text)
                    .font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            if file.truncatedBytes || file.truncatedLines {
                Text("Showing the first \(file.lineCount.formatted()) lines of a large file. Use Open for the rest.")
                    .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(HTB.amber.opacity(0.18), in: Capsule()).padding(.bottom, 10)
            }
        }
    }
}

private struct ImagePane: View {
    let url: URL
    let actualSize: Bool
    var body: some View {
        if let img = NSImage(contentsOf: url) {
            if actualSize {
                ScrollView([.vertical, .horizontal]) { Image(nsImage: img).padding(16) }
            } else {
                Image(nsImage: img).resizable().scaledToFit().padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("This image couldn't be read.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PDFPane: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous
        v.document = PDFDocument(url: url); return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// The system's own previewer: Office documents, audio, video, Keynote... It runs out of process.
private struct QuickLookPane: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.previewItem = url as NSURL; v.autostarts = true; return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }
    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
