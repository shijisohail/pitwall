import Testing
import Foundation
@testable import Pitwall

@Suite struct ModelTests {
    @Test func permissionModesMapToTheCLISpellings() {
        #expect(PermissionMode.manual.flag == "manual")
        #expect(PermissionMode.manual.control == "default")        // set_permission_mode still says "default"
        #expect(PermissionMode.acceptEdits.control == "acceptEdits")
        #expect(PermissionMode.allCases.count == 6)
        #expect(Set(PermissionMode.allCases.map(\.flag)).count == 6)
    }

    @Test func catalogParsesTheInitializeResponse() {
        let c = Catalog([
            "commands": [["name": "compact", "description": "Compact it", "argumentHint": "[focus]"]],
            "models": [["value": "opus", "displayName": "Opus", "description": "Big", "supportsEffort": true, "supportedEffortLevels": ["low", "high"]]],
            "available_output_styles": ["default", "Concise"],
            "claude_code_version": "9.9.9",
            "account": ["email": "a@b.c", "flag": true, "n": 3],
        ])
        #expect(c.commands.first?.hint == "[focus]")
        #expect(c.models.first?.levels == ["low", "high"])
        #expect(c.styles == ["default", "Concise"])
        #expect(c.version == "9.9.9")
        #expect(c.account["email"] == "a@b.c"); #expect(c.account["flag"] == "yes"); #expect(c.account["n"] == nil)
    }

    @Test func blockDecodesToolInputAndToleratesGarbage() {
        var b = Block(kind: .tool); b.inputJSON = #"{"file_path":"/x","n":2}"#
        #expect(b.input["file_path"] as? String == "/x")
        b.inputJSON = "{not json"
        #expect(b.input.isEmpty)
    }

    @Test func shellQuotingNeutralisesMetacharacters() {
        #expect(TerminalApp.quote("plain") == "'plain'")
        #expect(TerminalApp.quote("it's") == #"'it'\''s'"#)
        #expect(TerminalApp.quote("$(rm -rf ~); `x`") == "'$(rm -rf ~); `x`'")
        #expect(TerminalApp.quote("") == "''")
    }

    @Test func toolSummariesAreReadable() {
        var b = Block(kind: .tool); b.toolName = "Read"; b.inputJSON = #"{"file_path":"\#(NSHomeDirectory())/proj/a.swift"}"#
        #expect(b.toolSummary == "~/proj/a.swift")
        b.toolName = "Grep"; b.inputJSON = #"{"pattern":"TODO"}"#
        #expect(b.toolSummary == "TODO")
    }
}
