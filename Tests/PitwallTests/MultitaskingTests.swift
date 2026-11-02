import Testing
import Foundation
@testable import Pitwall

@MainActor @Suite struct BackgroundTaskTests {
    private func ev(_ sub: String, _ f: [String: Any] = [:]) -> [String: Any] { ["type": "system", "subtype": sub].merging(f) { $1 } }
    private func started(_ c: Conversation, _ id: String = "t1", backgrounded: Bool = false, type: String = "local_bash") {
        c.handle(ev("task_started", ["task_id": id, "run_id": "r", "tool_use_id": "toolu_\(id)", "description": "cmd \(id)",
                                     "is_backgrounded": backgrounded, "task_type": type]))
    }

    @Test func aStartedCommandIsTrackedButAnAgentIsLeftToTheAgentView() {
        let c = Conversation(cwd: "/tmp")
        started(c, "t1"); started(c, "a1", type: "local_agent")
        #expect(c.tasks.map(\.id) == ["t1"])
        #expect(c.tasks[0].isRunning && c.tasks[0].canBackground)
        #expect(c.tasks[0].title == "cmd t1" && c.tasks[0].toolUseID == "toolu_t1")
    }

    @Test func backgroundingAndStoppingUpdateTheTask() {
        let c = Conversation(cwd: "/tmp"); started(c)
        c.handle(ev("task_updated", ["task_id": "t1", "patch": ["is_backgrounded": true]]))
        #expect(c.tasks[0].isBackgrounded && !c.tasks[0].canBackground && c.foregroundTasks.isEmpty)
        c.handle(ev("task_updated", ["task_id": "t1", "patch": ["status": "killed", "end_time": 1_793_583_301_079]]))
        #expect(c.tasks[0].status == .stopped)
        #expect(c.tasks[0].endedAt == Date(timeIntervalSince1970: 1_793_583_301.079))
        #expect(c.runningTasks.isEmpty)
    }

    @Test func aNotificationFinishesTheTaskAndRecordsItsLog() {
        let c = Conversation(cwd: "/tmp"); started(c, backgrounded: true)
        c.handle(ev("task_notification", ["task_id": "t1", "status": "completed", "output_file": "/tmp/t1.output", "summary": "s"]))
        #expect(c.tasks[0].status == .completed && c.tasks[0].outputFile == "/tmp/t1.output" && c.tasks[0].endedAt != nil)
        c.handle(ev("task_notification", ["task_id": "nope", "status": "completed"]))     // unknown id: ignored
        #expect(c.tasks.count == 1)
    }

    @Test func theLiveListEndsOnlyBackgroundedTasksThatLeftIt() {
        let c = Conversation(cwd: "/tmp")
        started(c, "bg", backgrounded: true); started(c, "fg", backgrounded: false)
        c.handle(ev("background_tasks_changed", ["tasks": [["task_id": "bg"]]]))
        #expect(c.runningTasks.count == 2)
        c.handle(ev("background_tasks_changed", ["tasks": [] as [[String: Any]]]))
        #expect(c.tasks.first { $0.id == "bg" }?.status == .completed)
        #expect(c.tasks.first { $0.id == "fg" }?.status == .running)      // a foreground command was never in that list
    }

    @Test func onlyTheNewestFinishedTasksAreKept() {
        let c = Conversation(cwd: "/tmp")
        for i in 0..<10 {
            started(c, "t\(i)")
            c.handle(ev("task_notification", ["task_id": "t\(i)", "status": "completed"]))
        }
        started(c, "live")
        #expect(c.tasks.filter { !$0.isRunning }.count == Conversation.finishedTasksKept)
        #expect(c.tasks.contains { $0.id == "live" } && c.tasks.contains { $0.id == "t9" } && !c.tasks.contains { $0.id == "t0" })
    }

    @Test func whenTheProcessIsGoneEveryTaskHasEnded() {
        let c = Conversation(cwd: "/tmp"); started(c, "a"); started(c, "b", backgrounded: true)
        c.endAllTasks()
        #expect(c.runningTasks.isEmpty && c.tasks.allSatisfy { $0.status == .stopped })
    }

    @Test func aFinishedTasksLogIsReadFromItsFile() {
        withTempDir { dir in
            let f = dir.appendingPathComponent("t.output")
            try? "line1\nline2\n".write(to: f, atomically: true, encoding: .utf8)
            #expect(Conversation.tail(ofFile: f.path) == "line1\nline2\n")
            try? String(repeating: "x", count: 50_000).write(to: f, atomically: true, encoding: .utf8)
            #expect(Conversation.tail(ofFile: f.path, maxBytes: 100)?.count == 100)
            #expect(Conversation.tail(ofFile: dir.appendingPathComponent("missing").path) == nil)
        }
    }
}

@Suite struct SideQuestionParsingTests {
    @Test func btwIsRecognisedOnlyAtTheStart() {
        #expect(Conversation.sideQuestion(in: "/btw what's the ETA?") == "what's the ETA?")
        #expect(Conversation.sideQuestion(in: "/BTW  how long?  ") == "how long?")
        #expect(Conversation.sideQuestion(in: "/btw") == "")
        #expect(Conversation.sideQuestion(in: "/btw\nmultiline question") == "multiline question")
        #expect(Conversation.sideQuestion(in: "/btwx nope") == nil)
        #expect(Conversation.sideQuestion(in: "please /btw this") == nil)
        #expect(Conversation.sideQuestion(in: "btw something") == nil)
        #expect(Conversation.sideQuestion(in: "/review") == nil)
    }
}

@MainActor @Suite struct LiveShellTests {
    private func run(_ cmd: String, cwd: String = NSTemporaryDirectory(), stopAfter: Double? = nil)
        async -> (output: String, status: Int32, cwd: String?, stopped: Bool, streamed: [String])? {
        let sh = LiveShell()
        var result: (String, Int32, String?, Bool)?
        var streamed: [String] = []
        sh.onOutput = { streamed.append($0) }
        sh.onFinish = { o, s, c, st in result = (o, s, c, st) }
        sh.start(cmd, cwd: cwd)
        if let t = stopAfter { try? await Task.sleep(for: .seconds(t)); sh.stop() }
        guard await waitUntil(15, { result != nil }), let r = result else { return nil }
        return (r.0, r.1, r.2, r.3, streamed)
    }

    @Test func scriptAndSplitAreInverse() {
        let s = LiveShell.script("echo hi", in: "/tmp/it's here")
        #expect(s.contains("'/tmp/it'\\''s here'"))                    // the folder is quoted safely
        let (out, cwd) = LiveShell.split("one\ntwo\n\n\(LiveShell.marker)/usr/local\n")
        #expect(out == "one\ntwo" && cwd == "/usr/local")
        #expect(LiveShell.split("no marker\n").cwd == nil)
        #expect(LiveShell.split("\n\(LiveShell.marker)/x\n").output == "")
    }

    @Test func outputAndTheExitStatusComeBack() async {
        let r = await run("echo one; echo two; exit 3")
        #expect(r?.output == "one\ntwo"); #expect(r?.status == 3); #expect(r?.stopped == false)
    }

    @Test func stderrIsShownToo() async {
        let r = await run("echo out; echo err 1>&2")
        #expect(r?.output.contains("out") == true && r?.output.contains("err") == true)
    }

    @Test func outputStreamsBeforeTheCommandFinishes() async {
        let r = await run("echo first; sleep 1; echo second")
        #expect(r?.output == "first\nsecond")
        #expect(r?.streamed.contains { $0 == "first" } == true)         // seen while it was still running
    }

    @Test func cdCarriesOverToTheFolderReportedAtTheEnd() async {
        let r = await run("cd /usr && pwd")
        #expect(r?.output == "/usr"); #expect(r?.cwd == "/usr")
        let again = await run("pwd", cwd: r?.cwd ?? "/")
        #expect(again?.output == "/usr")
    }

    @Test func aMissingFolderFallsBackToHome() async {
        let r = await run("pwd", cwd: "/definitely/not/here")
        #expect(r?.output == NSHomeDirectory())
    }

    @Test func stopEndsTheCommandAndItsChildren() async {
        let r = await run("sleep 31 & sleep 32; echo not reached", stopAfter: 0.5)
        #expect(r?.stopped == true)
        #expect(r?.output.contains("not reached") == false)
        try? await Task.sleep(for: .seconds(1))
        let left = await withCheckedContinuation { (k: CheckedContinuation<Int, Never>) in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-f", "sleep 3[12]"]
                let out = Pipe(); p.standardOutput = out
                try? p.run(); p.waitUntilExit()
                k.resume(returning: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").count)
            }
        }
        #expect(left == 0)                                              // no orphaned sleep left behind
    }

    @Test func aBackgroundChildHoldingThePipeDoesNotHangTheCard() async {
        let r = await run("sleep 5 & echo done")
        #expect(r?.output == "done")
    }

    @Test func theConversationShowsALiveCardThatEnds() async {
        let c = Conversation(cwd: NSTemporaryDirectory())
        c.runLocal("echo hello; cd /usr")
        #expect(c.messages.last?.blocks.first?.live == true)
        #expect(await waitUntil { c.messages.last?.blocks.first?.live == nil && c.runningShells.isEmpty })
        #expect(c.messages.last?.blocks.first?.text == "hello")
        #expect(c.shellCwd == "/usr")
        #expect(c.queuedLocal.count == 1 && c.queuedLocal[0].hasPrefix("$ echo hello; cd /usr"))
        c.runLocal("pwd")
        #expect(await waitUntil { c.messages.last?.blocks.first?.live == nil && c.runningShells.isEmpty })
        #expect(c.messages.last?.blocks.first?.text == "/usr")          // the next command starts where `cd` left off
    }

    @Test func stoppingLeavesAStoppedCardAndANote() async {
        let c = Conversation(cwd: NSTemporaryDirectory())
        c.runLocal("sleep 30")
        try? await Task.sleep(for: .milliseconds(400))
        c.stopAllShells()
        #expect(await waitUntil { c.messages.last?.blocks.first?.live == nil })
        #expect(c.messages.last?.blocks.first?.text.contains("[stopped]") == true)
    }
}

@Suite struct FileViewingTests {
    private func write(_ dir: URL, _ name: String, _ data: Data) -> URL {
        let u = dir.appendingPathComponent(name); try? data.write(to: u); return u
    }
    private func text(_ s: String) -> Data { Data(s.utf8) }

    @Test func kindsByExtensionAndContent() {
        withTempDir { d in
            #expect(FileViewing.kind(for: write(d, "a.md", text("# hi"))) == .markdown)
            #expect(FileViewing.kind(for: write(d, "B.MARKDOWN", text("x"))) == .markdown)
            #expect(FileViewing.kind(for: write(d, "c.json", text("{}"))) == .json)
            #expect(FileViewing.kind(for: write(d, "d.PNG", Data([0x89, 0x50, 0x4E, 0x47, 0]))) == .image)
            #expect(FileViewing.kind(for: write(d, "e.pdf", text("%PDF-1.4"))) == .pdf)
            #expect(FileViewing.kind(for: write(d, "f.swift", text("let x = 1\n"))) == .text)
            #expect(FileViewing.kind(for: write(d, "NOEXT", text("héllo wörld\n"))) == .text)
            #expect(FileViewing.kind(for: write(d, "empty", Data())) == .text)
            #expect(FileViewing.kind(for: write(d, "run.sh", text("#!/bin/sh\necho hi\n"))) == .text)       // a script is just text to read
            #expect(FileViewing.kind(for: write(d, "data.bin", Data([0, 1, 2, 3, 0, 255]))) == .quickLook)
            #expect(FileViewing.kind(for: d.appendingPathComponent("missing.txt")) == .missing)
        }
    }

    @Test func foldersAndRealBinariesAreNeverOpenedFromHere() {
        withTempDir { d in
            #expect(FileViewing.kind(for: d) == .folder)
            let app = d.appendingPathComponent("Thing.app"); try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            #expect(FileViewing.kind(for: app) == .reveal)
            #expect(FileViewing.kind(for: write(d, "setup.pkg", Data([0, 1]))) == .reveal)
            let exe = write(d, "tool", Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0]))
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            #expect(FileViewing.kind(for: exe) == .reveal)                                                   // an executable binary
        }
    }

    @Test func aSymlinkIsJudgedByItsTarget() {
        withTempDir { d in
            let real = write(d, "real.md", text("# x"))
            let link = d.appendingPathComponent("link"); try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            #expect(FileViewing.kind(for: link) == .markdown)
        }
    }

    @Test func textIsCappedInLinesAndInBytes() {
        withTempDir { d in
            let small = FileViewing.loadText(write(d, "s.txt", text("a\nb\nc")))
            #expect(small?.text == "a\nb\nc" && small?.lineCount == 3 && small?.truncatedLines == false && small?.truncatedBytes == false)

            let many = FileViewing.loadText(write(d, "m.txt", text((1...6_000).map(String.init).joined(separator: "\n"))))
            #expect(many?.truncatedLines == true && many?.lineCount == FileViewing.maxLines)
            #expect(many?.text.split(separator: "\n").count == FileViewing.maxLines)

            let big = FileViewing.loadText(write(d, "b.txt", Data(repeating: 0x61, count: FileViewing.maxTextBytes + 10)))
            #expect(big?.truncatedBytes == true && big?.totalBytes == FileViewing.maxTextBytes + 10)
            #expect(FileViewing.loadText(d.appendingPathComponent("nope")) == nil)
        }
    }

    @Test func jsonIsPrettyPrintedOrLeftAlone() {
        let p = FileViewing.prettyJSON("{\"b\":1,\"a\":[1,2],\"u\":\"http://x/y\"}")
        #expect(p?.contains("\n") == true)
        if let p, let a = p.range(of: "\"a\""), let b = p.range(of: "\"b\"") { #expect(a.lowerBound < b.lowerBound) }    // keys sorted
        #expect(p?.contains("http://x/y") == true)                                                                          // slashes not escaped
        #expect(FileViewing.prettyJSON("{not json") == nil)
        #expect(FileViewing.prettyJSON("") == nil)
    }
}
