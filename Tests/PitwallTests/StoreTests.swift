import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite struct StoreTests {
    private func add(_ s: Store, cwd: String, entrypoint: String? = "cli", id: String = UUID().uuidString) -> Conversation {
        let c = Conversation(meta: sessionMeta(id: id, cwd: cwd, entrypoint: entrypoint)); c.store = s
        s.conversations.append(c); return c
    }

    @Test func ownerIsTheDeepestOpenedFolder() {
        let s = makeStore()
        s.workspace = ["/work", "/work/app"]
        #expect(s.owner(ofPath: "/work/app/sub") == "/work/app")
        #expect(s.owner(ofPath: "/work/other") == "/work")
        #expect(s.owner(ofPath: "/workshop") == nil)           // prefix must end at a path boundary
        #expect(s.owner(ofPath: "/elsewhere") == nil)
    }

    @Test func onlyOpenedProjectsAreShown() {
        let s = makeStore()
        let a = add(s, cwd: "/work/app"), b = add(s, cwd: "/work/other")
        s.workspace = ["/work/app"]
        #expect(s.filtered.map(\.id) == [a.id])
        #expect(s.search("", all: false).map(\.id) == [a.id])
        #expect(Set(s.search("", all: true).map(\.id)) == [a.id, b.id])
        #expect(s.projects.map(\.path) == ["/work/app"])
    }

    @Test func scriptSessionsAreHiddenUnlessOwnedOrToggled() {
        let s = makeStore()
        s.workspace = ["/w"]
        let cli = add(s, cwd: "/w"), sdk = add(s, cwd: "/w", entrypoint: "sdk-cli")
        #expect(s.filtered.map(\.id) == [cli.id])
        s.markOwned(sdk.id)
        #expect(Set(s.filtered.map(\.id)) == [cli.id, sdk.id])
        s.showAutomation = true
        #expect(s.hiddenAutomationCount == 0)
    }

    @Test func recentProjectsListsUnopenedFoldersThatExist() throws {
        try withTempDir { dir in
            let s = makeStore()
            let real = dir.appendingPathComponent("real").path
            try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
            _ = add(s, cwd: real); _ = add(s, cwd: real); _ = add(s, cwd: "/gone/\(UUID().uuidString)")
            let r = s.recentProjects()
            #expect(r.map(\.path) == [real]); #expect(r.first?.count == 2)
            s.workspace = [real]
            #expect(s.recentProjects().isEmpty)
        }
    }

    @Test func openFolderAddsToWorkspaceAndStartsASessionWhenThereIsNoHistory() {
        let s = makeStore()
        s.openFolder("/work/new")
        #expect(s.workspace == ["/work/new"])
        #expect(s.current?.cwd == "/work/new")
        #expect(s.tabs.count == 1)
        #expect(s.showBoard == false)
    }

    @Test func openFolderWithHistoryShowsTheBoardFocusedOnIt() {
        let s = makeStore()
        _ = add(s, cwd: "/work/app")
        s.openFolder("/work/app")
        #expect(s.showBoard); #expect(s.focusProject == "/work/app")
    }

    @Test func closeFolderHidesItAndDropsItsTabs() {
        let s = makeStore()
        let a = add(s, cwd: "/w/a"), b = add(s, cwd: "/w/b")
        s.workspace = ["/w/a", "/w/b"]
        s.open(a); s.open(b)
        s.closeFolder("/w/a")
        #expect(s.workspace == ["/w/b"])
        #expect(s.tabs == [b.id])
        #expect(s.filtered.map(\.id) == [b.id])
        #expect(s.conversations.contains { $0.id == a.id })     // history is never deleted, only hidden
    }

    @Test func openingASessionOutsideTheWorkspacePullsItsFolderIn() {
        let s = makeStore()
        let c = add(s, cwd: "/elsewhere/x")
        s.open(c)
        #expect(s.workspace == ["/elsewhere/x"])
    }

    // MARK: Tabs

    @Test func openingSessionsCreatesTabsOnce() {
        let s = makeStore(); s.workspace = ["/w"]
        let a = add(s, cwd: "/w"), b = add(s, cwd: "/w")
        s.open(a); s.open(b); s.open(a)
        #expect(s.tabs == [a.id, b.id])
        #expect(s.selection == a.id)
    }

    @Test func closingTheActiveTabSelectsItsNeighbourAndTheLastOneShowsTheBoard() {
        let s = makeStore(); s.workspace = ["/w"]
        let a = add(s, cwd: "/w"), b = add(s, cwd: "/w"), c = add(s, cwd: "/w")
        [a, b, c].forEach { s.open($0) }
        s.closeTab(c.id); #expect(s.selection == b.id)
        s.selectTab(a.id); s.closeTab(a.id); #expect(s.selection == b.id)
        s.closeTab(b.id)
        #expect(s.tabs.isEmpty); #expect(s.selection == nil); #expect(s.showBoard)
    }

    @Test func closingABlankNewTabDiscardsTheSession() {
        let s = makeStore()
        s.newConversation(cwd: "/w/fresh")
        let id = s.selection!
        s.closeTab(id)
        #expect(!s.conversations.contains { $0.id == id })
    }

    @Test func tabsCycleAndReorder() {
        let s = makeStore(); s.workspace = ["/w"]
        let a = add(s, cwd: "/w"), b = add(s, cwd: "/w"), c = add(s, cwd: "/w")
        [a, b, c].forEach { s.open($0) }
        s.cycleTab(1); #expect(s.selection == a.id)           // wraps from the last tab
        s.cycleTab(-1); #expect(s.selection == c.id)
        s.moveTab(c.id, before: a.id)
        #expect(s.tabs == [c.id, a.id, b.id])
    }

    @Test func closeOtherTabsAndTabsToTheRight() {
        let s = makeStore(); s.workspace = ["/w"]
        let cs = (0..<4).map { _ in add(s, cwd: "/w") }
        cs.forEach { s.open($0) }
        s.closeTabs(after: cs[1].id)
        #expect(s.tabs == [cs[0].id, cs[1].id])
        s.closeOtherTabs(cs[0].id)
        #expect(s.tabs == [cs[0].id]); #expect(s.selection == cs[0].id)
    }

    @Test func sessionsStartedInPitwallStayVisibleUnderTheirDiskId() {
        let s = makeStore(); s.workspace = ["/w"]
        let c = Conversation(cwd: "/w"); c.store = s
        c.sessionID = "disk-id"; c.historyPath = "/dev/null"; c.entrypoint = "sdk-cli"   // what a rescan makes of a Pitwall-run session
        s.conversations.append(c); s.markOwned("disk-id")
        #expect(s.filtered.contains { $0.id == c.id })
        #expect(s.hiddenAutomationCount == 0)
    }

    @Test func tabsPersistTheDurableSessionId() {
        let d = UserDefaults(suiteName: "pitwall-tests-\(UUID().uuidString)")!
        let s = Store(defaults: d); s.workspace = ["/w"]
        let c = Conversation(cwd: "/w"); c.store = s; c.sessionID = "disk-id"
        s.conversations.append(c); s.tabs = [c.id]
        #expect(d.stringArray(forKey: "tabs") == ["disk-id"])
    }

    @Test func workspaceAndTabsPersistAcrossLaunches() {
        let suite = "pitwall-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let s1 = Store(defaults: d)
        s1.workspace = ["/w"]; s1.tabs = ["x", "y"]
        let s2 = Store(defaults: d)
        #expect(s2.workspace == ["/w"]); #expect(s2.tabs == ["x", "y"])
    }
}
