import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite struct CommandTests {
    private func make() -> (Store, Conversation) {
        let s = makeStore()
        let c = Conversation(cwd: "/tmp"); c.store = s
        s.conversations.append(c); s.workspace = ["/tmp"]
        return (s, c)
    }
    private func forwarded(_ r: SlashRoute) -> String? { if case .forward(let t) = r { return t }; return nil }
    private func isHandled(_ r: SlashRoute) -> Bool { if case .handled = r { return true }; return false }

    @Test func skillsAndHeadlessCommandsAreForwardedUnchanged() {
        let (_, c) = make()
        #expect(forwarded(c.routeSlash("/context")) == "/context")
        #expect(forwarded(c.routeSlash("/compact keep the API notes")) == "/compact keep the API notes")
        #expect(forwarded(c.routeSlash("/my-plugin:do-thing arg")) == "/my-plugin:do-thing arg")
    }

    @Test func reviewIsAnAliasOfCodeReview() {
        let (_, c) = make()
        #expect(forwarded(c.routeSlash("/review high 12")) == "/code-review high 12")
        #expect(forwarded(c.routeSlash("/review")) == "/code-review")
    }

    @Test func planSwitchesModeLocally() {
        let (_, c) = make()
        #expect(isHandled(c.routeSlash("/plan")))
        #expect(c.permission == .plan)
    }

    @Test func clearStartsANewSession() {
        let (s, c) = make()
        c.messages = [ChatMessage(role: .user, blocks: [Block(kind: .text, text: "hi")])]      // a blank session would just be reused
        let before = s.conversations.count
        #expect(isHandled(c.routeSlash("/clear")))
        #expect(s.conversations.count == before + 1)
        #expect(s.current?.id != c.id)
    }

    @Test func renameWithoutALiveProcessRetitlesLocally() {
        let (_, c) = make()
        #expect(isHandled(c.routeSlash("/rename Shiny name")))
        #expect(c.title == "Shiny name")
    }

    @Test func terminalOnlyCommandsExplainThemselves() {
        let (_, c) = make()
        #expect(isHandled(c.routeSlash("/vim")))
        #expect(c.messages.last?.blocks.first?.kind == .notice)
    }

    @Test func addDirRecordsExistingFoldersOnly() throws {
        try withTempDir { dir in
            let (_, c) = make()
            _ = c.routeSlash("/add-dir \(dir.path)")
            #expect(c.additionalDirs == [dir.path])
            _ = c.routeSlash("/add-dir /definitely/not/here")
            #expect(c.additionalDirs.count == 1)
        }
    }

    @Test func sheetsOpenForInteractiveCommands() {
        let (s, c) = make()
        _ = c.routeSlash("/memory"); #expect(s.sheet == .memory)
        _ = c.routeSlash("/mcp"); #expect(s.sheet == .mcp)
        _ = c.routeSlash("/resume"); #expect(s.sheet == .switcher)
        _ = c.routeSlash("/permissions"); #expect(s.sheet == .config("permissions"))
        #expect(forwarded(c.routeSlash("/mcp reconnect all")) == "/mcp reconnect all")   // with arguments the CLI handles it
    }

    @Test func sendReportsWhetherItConsumedTheInput() {
        let (_, c) = make()
        #expect(c.send("   ") == false)                       // nothing to send: the composer must keep the draft
        c.loadState = .loading
        #expect(c.send("hello") == false)                     // still loading history
        c.loadState = .loaded
        #expect(c.send("/plan") == true)                      // handled locally counts as consumed
    }

    @Test func everyNativeCommandHasADescription() {
        #expect(nativeCommands.allSatisfy { !$0.description.isEmpty && $0.native })
        #expect(Set(nativeCommands.map(\.name)).count == nativeCommands.count)
    }
}
