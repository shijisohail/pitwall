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
