import Testing
import Foundation
@testable import Pitwall

@Suite struct WorktreeNameTests {
    @Test func theNameAndRootComeFromTheCliPath() {
        #expect(Worktrees.name(inPath: "/Users/me/app/.claude/worktrees/fix-login") == "fix-login")
        #expect(Worktrees.name(inPath: "/Users/me/app/.claude/worktrees/fix-login/Sources") == "fix-login")
        #expect(Worktrees.root(ofPath: "/Users/me/app/.claude/worktrees/fix-login") == "/Users/me/app")
        #expect(Worktrees.name(inPath: "/Users/me/app") == nil && Worktrees.root(ofPath: "/Users/me/app") == nil)
        #expect(Worktrees.name(inPath: "/Users/me/app/.claude/worktrees/") == nil)
        #expect(Worktrees.path(root: "/r", name: "x") == "/r/.claude/worktrees/x")
    }

    @Test func namesAreMadeSafeForADirectoryAndABranch() {
        #expect(Worktrees.sanitize("Fix the login bug!") == "Fix-the-login-bug")
        #expect(Worktrees.sanitize("  feat/new  thing ") == "feat-new-thing")
        #expect(Worktrees.sanitize("../../etc") == "etc")
        #expect(Worktrees.sanitize("a..b") == "a.b")
        #expect(Worktrees.sanitize("release.lock") == "release")
        #expect(Worktrees.sanitize("---") == "" && Worktrees.sanitize("日本語") == "")
        #expect(Worktrees.sanitize(String(repeating: "x", count: 100)).count == 48)
    }

    @Test func aSuggestedNameIsShortAndSafe() {
        let n = Worktrees.suggestedName()
        #expect(n.hasPrefix("pitwall-") && n.count == 12)
        #expect(Worktrees.sanitize(n) == n)
        #expect(Worktrees.suggestedName(random: { 0 }) == "pitwall-aaaa")
    }
}

@MainActor @Suite(.serialized) struct WorktreeSessionTests {
    private func make(_ cwd: String = "/tmp") -> Conversation {
        let c = Conversation(cwd: cwd); c.store = makeStore(); return c
    }

    @Test func aNewSessionLaunchesWithTheWorktreeFlagOnlyOnce() {
        let c = make()
        #expect(c.launchOptions().extraArgs.contains("--worktree") == false)
        c.worktreeName = "wt1"
        let a = c.launchOptions().extraArgs
        #expect(a.suffix(2) == ["--worktree", "wt1"])
        c.sessionID = "s1"                       // once it exists, resuming re-enters the worktree by itself
        #expect(c.launchOptions().extraArgs.contains("--worktree") == false)
        let f = make(); f.worktreeName = "wt2"; f.forkFrom = "s0"
        #expect(f.launchOptions().extraArgs.contains("--worktree") == false)
    }

    @Test func theInitEventMovesTheSessionIntoTheWorktreeItWasGiven() {
        let c = make("/tmp/proj"); c.worktreeName = "wt1"
        #expect(c.worktreeLabel == "wt1" && !c.inWorktree && c.canChooseWorktree)
        c.handle(["type": "system", "subtype": "init", "session_id": "s1", "cwd": "/tmp/proj/.claude/worktrees/wt1", "original_cwd": "/tmp/proj"])
        #expect(c.cwd == "/tmp/proj/.claude/worktrees/wt1")
        #expect(c.inWorktree && c.worktreeLabel == "wt1" && !c.canChooseWorktree)
        #expect(c.sessionID == "s1")
    }

    @Test func anOrdinaryInitLeavesTheFolderAlone() {
        let c = make("/tmp/proj")
        c.handle(["type": "system", "subtype": "init", "session_id": "s1", "cwd": "/tmp/proj/sub"])
        #expect(c.cwd == "/tmp/proj")
        c.handle(["type": "system", "subtype": "init", "session_id": "s1"])
        #expect(c.cwd == "/tmp/proj" && !c.inWorktree && c.worktreeLabel == nil)
    }

    @Test func theCommandCatalogFollowsTheSessionIntoTheWorktree() {
        let c = make("/tmp/proj")
        c.store?.catalogs["/tmp/proj"] = Catalog()
        c.handle(["type": "system", "subtype": "init", "cwd": "/tmp/proj/.claude/worktrees/w"])
        #expect(c.store?.catalogs["/tmp/proj/.claude/worktrees/w"] != nil)
    }

    @Test func aSessionResumedFromHistoryKnowsItIsInAWorktree() {
        let c = Conversation(meta: sessionMeta(cwd: "/tmp/proj/.claude/worktrees/old"))
        #expect(c.inWorktree && c.worktreeLabel == "old")
        #expect(!c.canChooseWorktree)
    }

    @Test func aDeletedWorktreeFallsBackToItsRepository() {
        withTempDir { dir in
            let root = dir.path
            let gone = Worktrees.path(root: root, name: "removed")
            let c = Conversation(cwd: gone)
            #expect(c.launchDirectory == root)
            try? FileManager.default.createDirectory(atPath: gone, withIntermediateDirectories: true)
            #expect(c.launchDirectory == gone)                     // still there: launch inside it
            #expect(Conversation(cwd: "/definitely/not/here").launchDirectory == "/definitely/not/here")
        }
    }

    @Test func aSessionThatHasStartedCannotSwitchWorktreeOnOrOff() {
        let c = make()
        #expect(c.canChooseWorktree)
        c.messages.append(ChatMessage(role: .user, blocks: [Block(kind: .text, text: "hi")]))
        #expect(!c.canChooseWorktree)
        c.toggleWorktree()
        #expect(c.worktreeName == nil)
    }

    @Test func startingWithAMissingFolderFailsWithAClearMessage() {
        let c = Conversation(cwd: "/definitely/not/here")
        #expect(throws: (any Error).self) { try c.startRunner() }
    }
}

/// Real git: a throwaway repository with a worktree where the CLI would put one.
@Suite(.serialized) struct WorktreeGitTests {
    private func repo(_ dir: URL) -> String {
        let r = dir.path
        _ = Worktrees.git(["init", "-q", "-b", "main"], in: r)
        try? "hi\n".write(toFile: r + "/a.txt", atomically: true, encoding: .utf8)
        _ = Worktrees.git(["add", "."], in: r)
        _ = Worktrees.git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"], in: r)
        return r
    }

    @Test func aRepositoryIsRecognisedAndAPlainFolderIsNot() async {
        await withTempDirAsync { dir in
            #expect(await Worktrees.isGitRepo(dir.path) == false)
            let r = repo(dir)
            #expect(await Worktrees.isGitRepo(r))
        }
    }

    @Test func aCleanWorktreeIsRemovedWithItsBranchEvenWhenLockedLikeAClaudeDashPRun() async {
        await withTempDirAsync { dir in
            let r = repo(dir)
            let wt = Worktrees.path(root: r, name: "w1")
            #expect(Worktrees.git(["worktree", "add", "-q", "-b", "worktree-w1", wt], in: r).status == 0)
            _ = Worktrees.git(["worktree", "lock", wt], in: r)             // `-p` leaves Claude's lock behind
            #expect(await Worktrees.changedFiles(at: wt) == 0)
            #expect(await Worktrees.remove(path: wt, force: false) == .removed(branchKept: false))
            #expect(!FileManager.default.fileExists(atPath: wt))
            #expect(!Worktrees.git(["branch", "--list", "worktree-w1"], in: r).output.contains("worktree-w1"))
        }
    }

    @Test func aDirtyWorktreeIsNotRemovedWithoutForce() async {
        await withTempDirAsync { dir in
            let r = repo(dir)
            let wt = Worktrees.path(root: r, name: "w2")
            _ = Worktrees.git(["worktree", "add", "-q", "-b", "worktree-w2", wt], in: r)
            try? "new\n".write(toFile: wt + "/b.txt", atomically: true, encoding: .utf8)
            #expect(await Worktrees.changedFiles(at: wt) == 1)
            if case .failed = await Worktrees.remove(path: wt, force: false) {} else { Issue.record("a dirty worktree must not be removed without force") }
            #expect(FileManager.default.fileExists(atPath: wt + "/b.txt"))
            #expect(await Worktrees.remove(path: wt, force: true) == .removed(branchKept: false))
        }
    }

    @Test func aBranchWithUnmergedCommitsIsKept() async {
        await withTempDirAsync { dir in
            let r = repo(dir)
            let wt = Worktrees.path(root: r, name: "w3")
            _ = Worktrees.git(["worktree", "add", "-q", "-b", "worktree-w3", wt], in: r)
            try? "x\n".write(toFile: wt + "/c.txt", atomically: true, encoding: .utf8)
            _ = Worktrees.git(["add", "."], in: wt)
            _ = Worktrees.git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"], in: wt)
            #expect(await Worktrees.remove(path: wt, force: false) == .removed(branchKept: true))
            #expect(Worktrees.git(["branch", "--list", "worktree-w3"], in: r).output.contains("worktree-w3"))
        }
    }

    @Test func somethingThatIsNotAWorktreePathIsRefused() async {
        let r = await Worktrees.remove(path: "/tmp/not-a-worktree", force: true)
        if case .failed = r {} else { Issue.record("must refuse a path outside .claude/worktrees") }
    }
}
