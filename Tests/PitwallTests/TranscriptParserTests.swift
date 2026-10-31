import Testing
import Foundation
@testable import Pitwall

@Suite struct TranscriptParserTests {
    private var transcript: String {
        userRecord("hi")
        + assistantRecord(id: "m1", [["type": "text", "text": "Reading"]])
        + assistantRecord(id: "m1", [["type": "tool_use", "id": "t1", "name": "Read", "input": ["file_path": "/a/b.swift"]]])
        + toolResultRecord(id: "t1", "contents")
        + assistantRecord(id: "m2", [["type": "text", "text": "Done"]])
    }

    @Test func mergesBlocksOfOneMessageAndMatchesToolResults() {
        let p = TranscriptParser()
        p.consume(Data(transcript.utf8))
        #expect(p.messages.count == 3)
        #expect(p.messages[1].blocks.count == 2)
        #expect(p.messages[1].blocks[1].toolName == "Read")
        #expect(p.messages[1].blocks[1].result == "contents")
        #expect(p.messages[1].blocks[1].input["file_path"] as? String == "/a/b.swift")
    }

    @Test func chunkedParsingEqualsFullParsing() {
        let data = Data(transcript.utf8)
        let full = TranscriptParser(); full.consume(data)
        for size in [1, 3, 7, 50, 1000] {
            let inc = TranscriptParser()
            var i = 0
            while i < data.count { let n = min(size, data.count - i); inc.consume(data.subdata(in: i..<i + n)); i += n }
            #expect(inc.messages.map(\.blocks.count) == full.messages.map(\.blocks.count), "chunk size \(size)")
            #expect(inc.messages[1].blocks[1].result == "contents", "chunk size \(size)")
        }
    }

    @Test func aPartialTrailingLineWaitsForItsNewline() {
        let p = TranscriptParser()
        let line = userRecord("hello")
        p.consume(Data(line.dropLast(5).utf8))
        #expect(p.messages.isEmpty)
        p.consume(Data(line.suffix(5).utf8))
        #expect(p.messages.count == 1)
    }

    @Test func skipsInjectedSystemText() {
        let p = TranscriptParser()
        p.consume(Data((userRecord("<system-reminder>ignore</system-reminder>") + userRecord("<command-name>/x</command-name>") + userRecord("real prompt")).utf8))
        #expect(p.messages.count == 1)
        #expect(p.messages[0].blocks[0].text == "real prompt")
    }

    @Test func recordsCustomAndAITitles() {
        let p = TranscriptParser()
        p.consume(Data((jsonl(["type": "ai-title", "aiTitle": "Generated"]) + jsonl(["type": "custom-title", "customTitle": "Mine"])).utf8))
        #expect(p.aiTitle == "Generated")
        #expect(p.customTitle == "Mine")
    }

    @Test func decodesImages() {
        let png = Data("not really a png".utf8)
        let rec = jsonl(["type": "user", "message": ["role": "user", "content": [
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]],
            ["type": "text", "text": "what is this"]]]])
        let p = TranscriptParser(); p.consume(Data(rec.utf8))
        #expect(p.messages.first?.blocks.first?.kind == .image)
        #expect(p.messages.first?.blocks.first?.imageData == png)
    }

    @Test func compactBoundaryBecomesANotice() {
        let p = TranscriptParser()
        p.consume(Data(jsonl(["type": "system", "subtype": "compact_boundary"]).utf8))
        #expect(p.messages.first?.blocks.first?.kind == .notice)
    }

    @Test func sidechainRecordsAreIgnored() {
        let p = TranscriptParser()
        p.consume(Data(jsonl(["type": "user", "isSidechain": true, "message": ["role": "user", "content": "subagent"]]).utf8))
        #expect(p.messages.isEmpty)
    }
}
