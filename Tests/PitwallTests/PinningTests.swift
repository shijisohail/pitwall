import Testing
import Foundation
@testable import Pitwall

/// Pinned chats: kept in pin order, listed once, and remembered by their durable session id.
@MainActor @Suite struct PinningTests {
    private func make(_ n: Int) -> (Store, [Conversation]) {
        let s = makeStore(); s.workspace = ["/tmp"]
        let cs = (0..<n).map { i -> Conversation in
            let c = Conversation(cwd: "/tmp"); c.store = s; c.title = "chat \(i)"
            c.messages = [ChatMessage(role: .user, blocks: [Block(kind: .text, text: "hi")])]     // a blank session isn't listed
            c.updatedAt = Date(timeIntervalSince1970: Double(i)); s.conversations.append(c); return c
        }
        return (s, cs)
    }

    @Test func pinningMovesAChatOutOfItsProjectIntoPinned() {
        let (s, c) = make(3)
        s.togglePin(c[0])
        #expect(s.isPinned(c[0]))
        #expect(s.pinnedConversations.map(\.id) == [c[0].id])
        #expect(!s.conversations(in: Project(path: "/tmp")).contains { $0.id == c[0].id })
        s.togglePin(c[0])
        #expect(s.pinnedConversations.isEmpty)
        #expect(s.conversations(in: Project(path: "/tmp")).contains { $0.id == c[0].id })
    }

    @Test func pinnedChatsKeepTheOrderTheyWerePinnedIn() {
        let (s, c) = make(3)
        s.togglePin(c[2]); s.togglePin(c[0])
        #expect(s.pinnedConversations.map(\.id) == [c[2].id, c[0].id])
    }

    @Test func aPinSurvivesTheChatGettingItsSessionIDAndARelaunch() {
        let d = UserDefaults(suiteName: "pitwall-tests-\(UUID().uuidString)")!
        let s = Store(defaults: d); s.workspace = ["/tmp"]
        let c = Conversation(cwd: "/tmp"); c.store = s; s.conversations.append(c)
        s.togglePin(c)
        c.sessionID = "durable-id"
        #expect(s.isPinned(c))
        s.persistPins()
        #expect(Store(defaults: d).pinned == ["durable-id"])
    }
}
