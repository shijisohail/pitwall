import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Turns whatever the user drags onto the chat (screenshots, image files, images dragged out of a browser,
/// plain files and folders) into composer attachments: images become thumbnails, everything else an `@path` mention.
enum DropIntake {
    static let types: [UTType] = [.fileURL, .image]

    /// `@path` text for a dropped file, relative to the session folder when it lives inside it.
    static func mention(for path: String, cwd: String) -> String {
        let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
        let rel = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
        return "@" + (rel.contains(" ") ? "\"\(rel)\"" : rel)
    }

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
    }

    /// Returns true when at least one provider looks like something we can use.
    @MainActor
    static func handle(_ providers: [NSItemProvider], into c: Conversation) -> Bool {
        var accepted = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in add(url, to: c) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in if let img = NSImage(data: data) { c.draftImages.append(img) } }
                }
            }
        }
        return accepted
    }

    @MainActor
    static func add(_ url: URL, to c: Conversation) {
        if isImage(url), let img = NSImage(contentsOf: url) { c.draftImages.append(img) }
        else { c.draftAppend.append(mention(for: url.path, cwd: c.cwd)) }
    }
}

private struct DropTarget: ViewModifier {
    let conversation: Conversation
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: DropIntake.types, isTargeted: $targeted) { DropIntake.handle($0, into: conversation) }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(HTB.green, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(HTB.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            Label("Drop to attach", systemImage: "tray.and.arrow.down.fill")
                                .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(8).allowsHitTesting(false).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

extension View {
    /// Makes the whole view accept dragged screenshots, images and files for `conversation`'s composer.
    func attachmentDrop(for conversation: Conversation) -> some View { modifier(DropTarget(conversation: conversation)) }
}
