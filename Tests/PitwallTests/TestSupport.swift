import Foundation
@testable import Pitwall

/// One JSONL record as a line.
func jsonl(_ o: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self) + "\n"
}

func userRecord(_ text: String, cwd: String? = nil, entrypoint: String? = nil, branch: String? = nil) -> String {
    var o: [String: Any] = ["type": "user", "message": ["role": "user", "content": text], "timestamp": "2026-10-31T10:00:00.000Z"]
    if let cwd { o["cwd"] = cwd }
    if let entrypoint { o["entrypoint"] = entrypoint }
    if let branch { o["gitBranch"] = branch }
    return jsonl(o)
}

func assistantRecord(id: String, _ blocks: [[String: Any]]) -> String {
    jsonl(["type": "assistant", "message": ["id": id, "role": "assistant", "content": blocks]])
}

func toolResultRecord(id: String, _ content: String, isError: Bool = false) -> String {
    jsonl(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": content, "is_error": isError]]]])
}

/// A throwaway directory, deleted when the closure returns.
func withTempDir<T>(_ body: (URL) throws -> T) rethrows -> T {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pitwall-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

/// Stores are retained for the whole test run: `Conversation.store` is weak, as in the app (where `Store.shared` lives forever).
nonisolated(unsafe) private var retainedStores: [Store] = []

@MainActor func makeStore() -> Store {
    let s = Store(defaults: UserDefaults(suiteName: "pitwall-tests-\(UUID().uuidString)")!)
    retainedStores.append(s)
    return s
}

func sessionMeta(id: String = UUID().uuidString, cwd: String, title: String = "t", entrypoint: String? = "cli", path: String = "/dev/null") -> SessionMeta {
    SessionMeta(id: id, path: path, cwd: cwd, title: title, date: Date(), branch: nil, entrypoint: entrypoint, searchText: title.lowercased())
}

/// Spins the main run loop (so the runner's main-queue callbacks are delivered) until `cond` holds.
@MainActor func waitUntil(_ timeout: Double = 10, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return cond()
}

/// A stand-in for `claude -p --input-format stream-json …` that speaks the real wire protocol
/// (see docs/CLAUDE_CODE_PROTOCOL.md). Behaviour is chosen by the prompt text:
///   "approve" → asks for tool approval and reports the verdict · "hang" → waits for an interrupt · otherwise → replies.
let fakeClaudeScript = #"""
#!/bin/bash
emit() { printf '%s\n' "$1"; }
sid="fake-session-1"
while IFS= read -r line; do
  rid=$(printf '%s' "$line" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
  case "$line" in
    *'"subtype":"initialize"'*)
      emit '{"type":"control_response","response":{"subtype":"success","request_id":"'"$rid"'","response":{"commands":[{"name":"fake-cmd","description":"d"}],"models":[],"claude_code_version":"0.0.0-fake"}}}' ;;
    *'"subtype":"interrupt"'*)
      emit '{"type":"control_response","response":{"subtype":"success","request_id":"'"$rid"'","response":{}}}'
      emit '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"'"$sid"'"}' ;;
    *'"type":"user"'*)
      emit '{"type":"system","subtype":"init","session_id":"'"$sid"'","model":"fake-model"}'
      case "$line" in
        *approve*)
          emit '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m1"}}}'
          emit '{"type":"control_request","request_id":"req1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/x","content":"hi"},"tool_use_id":"t1"}}'
          IFS= read -r reply
          case "$reply" in *'"behavior":"allow"'*) verdict="allowed" ;; *) verdict="denied" ;; esac
          emit '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}'
          emit '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"'"$verdict"'"}}}'
          emit '{"type":"result","subtype":"success","is_error":false,"result":"'"$verdict"'","session_id":"'"$sid"'","total_cost_usd":0.01}' ;;
        *hang*) : ;;
        *)
          emit '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m1"}}}'
          emit '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}'
          emit '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello from fake"}}}'
          emit '{"type":"result","subtype":"success","is_error":false,"result":"hello from fake","session_id":"'"$sid"'","total_cost_usd":0.02}' ;;
      esac ;;
  esac
done
"""#

/// Points the app at the fake CLI for the duration of `body`.
@MainActor func withFakeClaude<T>(_ body: () throws -> T) rethrows -> T {
    try withTempDir { dir in
        let path = dir.appendingPathComponent("claude")
        try? fakeClaudeScript.write(to: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        let saved = ClaudeRunner.pathOverride
        ClaudeRunner.pathOverride = path.path
        defer { ClaudeRunner.pathOverride = saved }
        return try body()
    }
}
