import Testing
import AppKit
@testable import Pitwall

@MainActor @Suite struct TypeToFocusTests {
    private func key(_ chars: String, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }

    @Test func printableKeysOnANonTextControlAreRedirected() {
        #expect(TypeToFocus.shouldTakeOver(key("a"), firstResponder: NSView()))
        #expect(TypeToFocus.shouldTakeOver(key("A", .shift), firstResponder: nil))
        #expect(TypeToFocus.shouldTakeOver(key("é"), firstResponder: NSView()))
        #expect(TypeToFocus.shouldTakeOver(key("ش"), firstResponder: NSView()))
        #expect(TypeToFocus.shouldTakeOver(key("å", .option), firstResponder: NSView()))
    }

    @Test func spaceIsLeftForButtonsAndScrolling() {
        #expect(!TypeToFocus.shouldTakeOver(key(" "), firstResponder: NSView()))
    }

    @Test func shortcutsAndNavigationKeysAreNeverTaken() {
        #expect(!TypeToFocus.shouldTakeOver(key("c", .command), firstResponder: NSView()))
        #expect(!TypeToFocus.shouldTakeOver(key("x", .control), firstResponder: NSView()))
        for special in ["\r", "\t", "\u{1B}", "\u{7F}", "\u{F700}", "\u{F702}", "\u{F728}", ""] {
            #expect(!TypeToFocus.shouldTakeOver(key(special), firstResponder: NSView()))
        }
    }

    @Test func nothingIsTakenWhileYouAreAlreadyTypingInATextField() {
        let editable = NSTextView(); editable.isEditable = true
        #expect(!TypeToFocus.shouldTakeOver(key("a"), firstResponder: editable))
        #expect(!TypeToFocus.shouldTakeOver(key("a"), firstResponder: NSTextField()))
        let readOnly = NSTextView(); readOnly.isEditable = false          // selected transcript text
        #expect(TypeToFocus.shouldTakeOver(key("a"), firstResponder: readOnly))
    }
}
