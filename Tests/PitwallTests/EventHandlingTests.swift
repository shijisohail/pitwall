import Testing
import Foundation
@testable import Pitwall

/// Feeds recorded-style stream-json events straight into a conversation (no process).
@MainActor @Suite struct EventHandlingTests {
    private func make() -> (Store, Conversation) {
        let s = makeStore()
        let c = Conversation(cwd: "/tmp"); c.store = s
        s.conversations.append(c)
        return (s, c)
    }
    private func stream(_ e: [String: Any], parent: Any = NSNull()) -> [String: Any] {
        ["type": "stream_event", "event": e, "parent_tool_use_id": parent]
    }
    private func result(_ text: String = "", sub: String = "success", isError: Bool = false) -> [String: Any] {
        ["type": "result", "subtype": sub, "is_error": isError, "result": text, "session_id": "s1", "total_cost_usd": 0.5]
    }

    @Test func streamedTextBecomesOneAssistantMessage() {
        let (_, c) = make(); c.isRunning = true
        c.handle(stream(["type": "message_start", "message": ["id": "m1", "usage": ["input_tokens": 10, "cache_read_input_tokens": 5]]]))
        c.handle(stream(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]]))
        c.handle(stream(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Hel"]]))
        c.handle(stream(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "lo"]]))
        c.handle(result("Hello"))
        #expect(c.messages.count == 1)
        #expect(c.messages[0].blocks[0].text == "Hello")
        #expect(!c.isRunning); #expect(c.cost == 0.5); #expect(c.sessionID == "s1"); #expect(c.contextTokens == 15)
    }

    @Test func toolInputStreamsThenIsReplacedByTheFinalInputAndGetsItsResult() {
        let (_, c) = make()
        c.handle(stream(["type": "message_start", "message": ["id": "m1"]]))
        c.handle(stream(["type": "content_block_start", "index": 0, "content_block": ["type": "tool_use", "id": "t1", "name": "Bash"]]))
        c.handle(stream(["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": "{\"comm"]]))
        #expect(c.messages[0].blocks[0].input.isEmpty)                      // partial JSON isn't parseable yet
        c.handle(["type": "assistant", "message": ["id": "m1", "content": [["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "ls"]]]]])
        c.handle(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "a\nb"]]]])
        let b = c.messages[0].blocks[0]
        #expect(b.input["command"] as? String == "ls"); #expect(b.result == "a\nb"); #expect(!b.isError)
    }

    @Test func subagentEventsDoNotLeakIntoTheMainTranscript() {
        let (_, c) = make()
        c.handle(stream(["type": "message_start", "message": ["id": "sub"]], parent: "toolu_1"))
        c.handle(["type": "assistant", "parent_tool_use_id": "toolu_1", "message": ["id": "sub", "content": []]])
        #expect(c.messages.isEmpty)
    }

    @Test func permissionRequestsBecomeApprovalsAndCancelsRemoveThem() {
        let (_, c) = make(); c.permission = .manual
        c.handle(["type": "control_request", "request_id": "r1", "request": ["subtype": "can_use_tool", "tool_name": "Write",
                  "input": ["file_path": "/x"], "permission_suggestions": [["type": "setMode", "mode": "acceptEdits", "destination": "session"]]]])
        c.handle(["type": "control_request", "request_id": "r2", "request": ["subtype": "can_use_tool", "tool_name": "AskUserQuestion", "input": ["questions": []]]])
        c.handle(["type": "control_request", "request_id": "r3", "request": ["subtype": "can_use_tool", "tool_name": "ExitPlanMode", "input": ["plan": "p"]]])
        #expect(c.approvals.map(\.kind) == [.tool, .question, .plan])
        #expect(c.approvals[0].suggestions.count == 1)
        c.handle(["type": "control_cancel_request", "request_id": "r2"])
        #expect(c.approvals.map(\.id) == ["r1", "r3"])
    }

    @Test func allowingWithASetModeSuggestionMirrorsTheModeInTheUI() {
        let (_, c) = make(); c.permission = .manual
        c.handle(["type": "control_request", "request_id": "r1", "request": ["subtype": "can_use_tool", "tool_name": "Write", "input": [:]]])
        let a = c.approvals[0]
        c.allow(a, remember: ["type": "setMode", "mode": "acceptEdits", "destination": "session"])
        #expect(c.approvals.isEmpty); #expect(c.permission == .acceptEdits)
        c.handle(["type": "control_request", "request_id": "r2", "request": ["subtype": "can_use_tool", "tool_name": "Bash", "input": [:]]])
        c.deny(c.approvals[0], message: "nope")
        #expect(c.approvals.isEmpty)
    }

    @Test func unknownControlRequestsAreRefusedNotCrashed() {
        let (_, c) = make()
        c.handle(["type": "control_request", "request_id": "x", "request": ["subtype": "hook_callback"]])
        #expect(c.approvals.isEmpty)
    }

    @Test func aStoppedTurnShowsAStoppedNoticeNotAnError() {
        let (_, c) = make(); c.isRunning = true; c.stopRequested = true
        c.handle(result(sub: "error_during_execution", isError: true))
        #expect(c.messages.last?.blocks.first?.kind == .notice); #expect(c.messages.last?.blocks.first?.text == "Stopped")
        #expect(!c.isRunning)
    }

    @Test func aFailedTurnShowsTheErrorText() {
        let (_, c) = make(); c.isRunning = true
        c.handle(result("Not logged in · Please run /login", isError: true))
        #expect(c.messages.last?.blocks.first?.kind == .error)
        #expect(c.messages.last?.blocks.first?.text.contains("/login") == true)
    }

    @Test func aSlashCommandWithNoAssistantReplyBecomesAnOutputCard() {
        let (_, c) = make(); c.lastPrompt = "/context"; c.isRunning = true
        c.handle(result("## Context Usage\nTokens: 1k"))
        let b = c.messages.last?.blocks.first
        #expect(b?.kind == .output); #expect(b?.toolName == "/context"); #expect(b?.text.contains("Tokens") == true)
    }

    @Test func rateLimitEventsFeedTheUsageMeters() {
        let (s, c) = make()
        c.handle(["type": "rate_limit_event", "rate_limit_info": ["unifiedWindows": [
            "five_hour": ["utilization": 0.25, "resetsAt": 1_800_000_000.0], "seven_day": ["utilization": 0.5, "resetsAt": 1_800_100_000.0]]]])
        #expect(s.usage?.fiveHour == 0.25); #expect(s.usage?.sevenDay == 0.5)
        #expect(s.usage?.fiveReset == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func systemEventsUpdateTitleModelAndCompactionNotices() {
        let (_, c) = make()
        c.handle(["type": "system", "subtype": "init", "session_id": "abc", "model": "claude-x"])
        #expect(c.sessionID == "abc"); #expect(c.modelName == "claude-x")
        c.handle(["type": "system", "subtype": "session_title_changed", "title": "Renamed"])
        #expect(c.title == "Renamed")
        c.handle(["type": "system", "subtype": "compact_boundary", "compact_metadata": ["pre_tokens": 48_000]])
        #expect(c.messages.last?.blocks.first?.text.contains("compacted") == true)
        #expect(c.messages.last?.blocks.first?.text.contains("48k") == true)
    }

    @Test func hugeToolResultsAreClippedToProtectMemory() {
        let (_, c) = make()
        c.handle(stream(["type": "message_start", "message": ["id": "m1"]]))
        c.handle(stream(["type": "content_block_start", "index": 0, "content_block": ["type": "tool_use", "id": "t1", "name": "Read"]]))
        c.handle(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": String(repeating: "x", count: 400_000)]]]])
        let n = c.messages[0].blocks[0].result?.count ?? 0
        #expect(n < Limits.toolResult + 200); #expect(c.messages[0].blocks[0].result?.contains("truncated") == true)
    }
}
