import Testing
import Foundation
@testable import Pitwall

/// These swap the global history roots, so they must not run in parallel.
@Suite(.serialized) struct HistoryTests {
    private func session(_ dir: URL, project: String = "-tmp-proj", id: String, _ body: String) {
        let d = dir.appendingPathComponent(project, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? body.write(to: d.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
    }

    @Test func indexesSessionsWithTitlePrecedenceAndMetadata() {
        withTempDir { dir in
            let saved = (History.root, History.historyFile)
            defer { (History.root, History.historyFile) = saved }
            History.root = dir; History.historyFile = dir.appendingPathComponent("none.jsonl")

            session(dir, id: "a", userRecord("first prompt here", cwd: "/work/app", entrypoint: "cli", branch: "main")
                    + jsonl(["type": "ai-title", "aiTitle": "AI title"]))
            session(dir, id: "b", userRecord("another", cwd: "/work/app", entrypoint: "sdk-cli")
                    + jsonl(["type": "ai-title", "aiTitle": "AI"]) + jsonl(["type": "custom-title", "customTitle": "Renamed"]))
            session(dir, id: "c", userRecord("no title at all", cwd: "/work/other"))
            session(dir, id: "empty", jsonl(["type": "ai-title", "aiTitle": "x"]))      // no user prompt → not a session

            let m = Dictionary(uniqueKeysWithValues: History.scan().map { ($0.id, $0) })
            #expect(m.count == 3)
            #expect(m["a"]?.title == "AI title"); #expect(m["a"]?.branch == "main"); #expect(m["a"]?.entrypoint == "cli")
            #expect(m["b"]?.title == "Renamed"); #expect(m["b"]?.entrypoint == "sdk-cli")
            #expect(m["c"]?.title == "no title at all"); #expect(m["c"]?.cwd == "/work/other")
            #expect(m["empty"] == nil)
        }
    }

    @Test func sessionsWhoseFirstRecordIsHugeAreStillIndexed() {
        withTempDir { dir in
            let saved = (History.root, History.historyFile)
            defer { (History.root, History.historyFile) = saved }
            History.root = dir; History.historyFile = dir.appendingPathComponent("none.jsonl")
            session(dir, id: "big", userRecord(String(repeating: "x", count: 300_000), cwd: "/work/app", entrypoint: "cli"))
            #expect(History.scan().map(\.id) == ["big"])
            #expect(History.scan().first?.cwd == "/work/app")
        }
    }

    @Test func rescansPickUpChangesAndSkipUnchangedFiles() throws {
        try withTempDir { dir in
            let saved = (History.root, History.historyFile)
            defer { (History.root, History.historyFile) = saved }
            History.root = dir; History.historyFile = dir.appendingPathComponent("none.jsonl")
            session(dir, id: "a", userRecord("hi", cwd: "/w", entrypoint: "cli"))
            #expect(History.scanAll().metas.first?.title == "hi")
            #expect(History.scanAll().metas.count == 1)             // second pass served from the cache
            Thread.sleep(forTimeInterval: 0.05)
            let url = dir.appendingPathComponent("-tmp-proj/a.jsonl")
            let h = try FileHandle(forWritingTo: url); try h.seekToEnd()
            try h.write(contentsOf: Data(jsonl(["type": "custom-title", "customTitle": "Renamed"]).utf8)); try h.close()
            #expect(History.scanAll().metas.first?.title == "Renamed")
            try FileManager.default.removeItem(at: url)
            #expect(History.scanAll().metas.isEmpty)                 // deleted transcripts drop out
        }
    }

    @Test func promptHistoryIsReadFromHistoryFile() {
        withTempDir { dir in
            let saved = History.historyFile
            defer { History.historyFile = saved }
            History.historyFile = dir.appendingPathComponent("history.jsonl")
            let lines = jsonl(["display": "run tests", "project": "/work/app", "sessionId": "a", "timestamp": 2.0])
                + jsonl(["display": "", "project": "/work/app"])
            try? lines.write(to: History.historyFile, atomically: true, encoding: .utf8)
            let e = History.promptEntries()
            #expect(e.count == 1)
            #expect(e[0].text == "run tests"); #expect(e[0].project == "/work/app")
        }
    }

    @Test func missingFilesYieldNothingInsteadOfCrashing() {
        let saved = (History.root, History.historyFile)
        defer { (History.root, History.historyFile) = saved }
        History.root = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"); History.historyFile = History.root
        #expect(History.scan().isEmpty)
        #expect(History.promptEntries().isEmpty)
    }
}
