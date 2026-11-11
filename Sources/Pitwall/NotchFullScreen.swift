import AppKit
import Observation
import SwiftUI

/// Where the notch sits, in the window's own coordinates, while the notch-aware full screen is on. The tab bar reads it
/// to put tabs on either side of the notch.
@MainActor @Observable
final class NotchLayout {
    static let shared = NotchLayout()
    var active = false
    /// x where the notch starts / ends, measured from the left edge of the screen, and the height of the notch row.
    var leftEdge: CGFloat = 0
    var rightEdge: CGFloat = 0
    var height: CGFloat = 0
}

/// A borderless window that can still take keyboard focus (AppKit says borderless windows can't by default).
private final class FullScreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full screen that uses the whole display, including the row beside the camera notch.
///
/// macOS's own full screen keeps windows below the notch (a plain window is clamped there even with the menu bar
/// hidden), so tabs can't sit beside it. Only a borderless window may cover that row, so when the setting is on we move
/// the session window's content into one, full-screen. The content view, and so all its SwiftUI state, is reparented,
/// not recreated, and goes back when you leave full screen.
@MainActor
final class NotchFullScreen: NSObject {
    static let shared = NotchFullScreen()

    private weak var mainWindow: NSWindow?
    private var fullScreenWindow: NSWindow?
    private var originalZoom: (target: AnyObject?, action: Selector?)?
    /// Swapping the content view out and back makes SwiftUI drop the window's resizable flag (which greys out the green
    /// button), so the window's settings are saved on the way in and put back on the way out.
    private var savedWindowState: (style: NSWindow.StyleMask, behavior: NSWindow.CollectionBehavior, minSize: NSSize, maxSize: NSSize)?

    var isFullScreen: Bool { fullScreenWindow != nil }

    /// Called with the window the app's content lives in. Ignores our own full-screen window.
    func attach(_ window: NSWindow?) {
        guard let window, !(window is FullScreenWindow), fullScreenWindow == nil else { return }
        mainWindow = window
        apply()
    }

    /// Re-applies the setting: takes over (or hands back) the green button and macOS's own full screen.
    func apply() {
        guard let window = mainWindow else { return }
        let on = AppSettings.shared.notchFullScreen
        if let zoom = window.standardWindowButton(.zoomButton) {
            if on, zoom.target !== self {
                originalZoom = (zoom.target, zoom.action)
                zoom.target = self; zoom.action = #selector(zoomClicked)
            } else if !on, let o = originalZoom {
                zoom.target = o.target; zoom.action = o.action; originalZoom = nil
            }
        }
        if on { window.collectionBehavior.insert(.fullScreenNone) } else { window.collectionBehavior.remove(.fullScreenNone) }
        if !on, isFullScreen { exit() }
    }

    @objc private func zoomClicked(_ sender: Any?) { toggle() }

    func toggle() { isFullScreen ? exit() : enter() }

    private func enter() {
        guard let main = mainWindow, let content = main.contentView, let screen = main.screen ?? NSScreen.main else { return }
        let fs = FullScreenWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        fs.isReleasedWhenClosed = false
        fs.isOpaque = false; fs.backgroundColor = .clear; fs.hasShadow = false
        fs.collectionBehavior = [.fullScreenNone]

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            let layout = NotchLayout.shared
            layout.leftEdge = left.maxX - screen.frame.minX
            layout.rightEdge = right.minX - screen.frame.minX
            layout.height = screen.safeAreaInsets.top
            layout.active = true
        }
        savedWindowState = (main.styleMask, main.collectionBehavior, main.contentMinSize, main.contentMaxSize)
        main.contentView = NSView()        // a window must give up the view before another can take it
        fs.contentView = content
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        fs.setFrame(screen.frame, display: true)
        fs.makeKeyAndOrderFront(nil)
        main.orderOut(nil)
        fullScreenWindow = fs
    }

    /// The red and yellow buttons while in full screen: leave it first, so the window comes back where it was.
    func exitAndClose() { let w = mainWindow; exit(); w?.performClose(nil) }
    func exitAndMinimize() { let w = mainWindow; exit(); w?.miniaturize(nil) }

    func exit() {
        guard let fs = fullScreenWindow else { return }
        fullScreenWindow = nil
        NotchLayout.shared.active = false
        NSApp.presentationOptions = []
        if let main = mainWindow, let content = fs.contentView {
            fs.contentView = NSView()
            main.contentView = content
            if let s = savedWindowState {
                main.styleMask = s.style; main.collectionBehavior = s.behavior
                main.contentMinSize = s.minSize; main.contentMaxSize = s.maxSize
            }
            main.makeKeyAndOrderFront(nil)
        }
        savedWindowState = nil
        fs.orderOut(nil)
    }
}

/// Close / minimise / leave full screen. The borderless full-screen window has no title bar, so no traffic lights.
struct FullScreenControls: View {
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            dot(Color(red: 1.0, green: 0.37, blue: 0.34), "xmark", "Close") { NotchFullScreen.shared.exitAndClose() }
            dot(Color(red: 1.0, green: 0.74, blue: 0.18), "minus", "Minimize") { NotchFullScreen.shared.exitAndMinimize() }
            dot(Color(red: 0.16, green: 0.78, blue: 0.25), "arrow.down.right.and.arrow.up.left", "Exit Full Screen") { NotchFullScreen.shared.exit() }
        }
        .onHover { hover = $0 }
    }

    private func dot(_ color: Color, _ glyph: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 12, height: 12)
                .overlay { Image(systemName: glyph).font(.system(size: 6.5, weight: .black)).foregroundStyle(.black.opacity(0.6)).opacity(hover ? 1 : 0) }
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
