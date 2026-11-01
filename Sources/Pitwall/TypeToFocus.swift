import SwiftUI
import AppKit

/// Typing works anywhere in the chat, as in a terminal: click the transcript, select some text, tap a button, then just
/// type. A printable keystroke that lands on something that isn't a text field is held back, the prompt box is focused,
/// and the original key events are replayed into it, so accents, input methods and undo behave exactly as if you had
/// clicked the box first. Shortcuts (⌘ or ⌃), Space, arrows, Return, Tab and Escape are never touched, so keyboard
/// activation of buttons and scrolling keep working.
///
/// Each chat window has its own prompt box, so each registers separately and only keystrokes in its own window count.
@MainActor
final class TypeToFocus {
    static let shared = TypeToFocus()

    private struct Attachment {
        weak var window: NSWindow?
        var focus: () -> Void
        var held: [NSEvent] = []          // keystrokes waiting for the prompt box to take focus, in order
    }
    private var attachments: [ObjectIdentifier: Attachment] = [:]
    private var monitor: Any?

    /// Called by a visible prompt box. `owner` identifies it; a window has one prompt box, so attaching replaces any
    /// other owner already registered for the same window (the chat in a window changed).
    func attach(owner: ObjectIdentifier, window: NSWindow, focus: @escaping () -> Void) {
        for (other, a) in attachments where other != owner && a.window === window { attachments[other] = nil }
        attachments[owner] = Attachment(window: window, focus: focus, held: attachments[owner]?.held ?? [])
        guard monitor == nil else { return }
        // Local monitors always run on the main thread; NSEvent just isn't declared Sendable, hence the wrapper.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let incoming = EventBox(event: event)
            return MainActor.assumeIsolated { EventBox(event: self.handle(incoming.event!)) }.event
        }
    }

    func detach(owner: ObjectIdentifier) {
        attachments[owner] = nil
        guard attachments.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private struct EventBox: @unchecked Sendable { let event: NSEvent? }

    // MARK: Decision

    /// The editable text view the user is typing into, if the first responder is one (SwiftUI's fields use a field editor).
    static func editor(_ responder: NSResponder?) -> NSTextView? {
        guard let tv = responder as? NSTextView, tv.isEditable else { return nil }
        return tv
    }

    /// Giving a text field focus from code selects all of its text, so the next keystroke would wipe a draft. When that
    /// has just happened in a chat's prompt box, move the caret to the end instead. Focus that came from a click is left
    /// exactly as clicked.
    func caretToEndIfAllSelected() {
        if let t = NSApp.currentEvent?.type, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(t) { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for a in self.attachments.values {
                guard let tv = Self.editor(a.window?.firstResponder) else { continue }
                let n = (tv.string as NSString).length
                if n > 0, tv.selectedRange == NSRange(location: 0, length: n) { tv.setSelectedRange(NSRange(location: n, length: 0)) }
            }
        }
    }

    private static func isPrintable(_ u: Unicode.Scalar) -> Bool {
        u.value >= 0x20 && u.value != 0x7F && !(0x80...0x9F).contains(u.value) && !(0xF700...0xF8FF).contains(u.value)   // not control or arrow/function keys
    }

    /// Should this keystroke be redirected into the prompt box?
    static func shouldTakeOver(_ e: NSEvent, firstResponder: NSResponder?) -> Bool {
        guard e.type == .keyDown, e.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        guard let s = e.characters, !s.isEmpty, s != " ", s.unicodeScalars.allSatisfy(isPrintable) else { return false }   // Space activates buttons and scrolls
        if editor(firstResponder) != nil || firstResponder is NSTextField { return false }     // already typing somewhere
        return true
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        // Only a chat window with a prompt box, never Settings, a sheet, an alert, a menu or a popover.
        guard let window = e.window, window.attachedSheet == nil, NSApp.modalWindow == nil,
              let owner = attachments.first(where: { $0.value.window === window })?.key else { return e }
        if !(attachments[owner]?.held.isEmpty ?? true) {                      // still waiting for focus: keep the order
            attachments[owner]?.held.append(e)
            if let tv = Self.editor(window.firstResponder) { flush(owner, tv) }   // focus has landed: don't wait for the next poll
            return nil
        }
        guard Self.shouldTakeOver(e, firstResponder: window.firstResponder) else { return e }
        attachments[owner]?.held = [e]
        attachments[owner]?.focus()
        replay(owner: owner, attempt: 0)
        return nil
    }

    /// Caret to the end of whatever is already in the box, then replay the held keystrokes. They go to the *front* of the
    /// event queue (last first), so any keys that arrived in the meantime come after them, never before.
    private func flush(_ owner: ObjectIdentifier, _ tv: NSTextView) {
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        let events = attachments[owner]?.held ?? []
        attachments[owner]?.held = []
        for e in events.reversed() { NSApp.postEvent(e, atStart: true) }       // the box has focus now, so these pass straight through
    }

    /// Wait (a few milliseconds at a time) until the prompt box really is first responder, put the caret at the end of
    /// whatever is already in it, then replay the held keystrokes.
    private func replay(owner: ObjectIdentifier, attempt: Int) {
        guard let window = attachments[owner]?.window else { attachments[owner] = nil; return }
        guard !(attachments[owner]?.held.isEmpty ?? true) else { return }       // already flushed by a later keystroke
        if let tv = Self.editor(window.firstResponder) { flush(owner, tv); return }
        guard attempt < 50 else { attachments[owner]?.held = []; return }       // it never took focus: drop, don't loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            MainActor.assumeIsolated { self?.replay(owner: owner, attempt: attempt + 1) }
        }
    }
}

/// Reports the window a view lives in, once when it appears and again only if it moves to another window. Reports nil
/// when the view goes away, so whoever registered can unregister. (Re-reporting on every SwiftUI update would race a
/// disappearing view into re-registering.)
struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    final class Coordinator {
        weak var window: NSWindow?
        var reported = false
        var onChange: ((NSWindow?) -> Void)?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let v = NSView(); report(v, context.coordinator); return v }
    func updateNSView(_ v: NSView, context: Context) { report(v, context.coordinator) }
    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) { coordinator.onChange?(nil); coordinator.onChange = nil }

    private func report(_ v: NSView, _ c: Coordinator) {
        c.onChange = onChange
        DispatchQueue.main.async { [weak v] in
            guard let v, c.onChange != nil else { return }
            let w = v.window
            if c.reported, c.window === w { return }
            c.reported = true; c.window = w; c.onChange?(w)
        }
    }
}
