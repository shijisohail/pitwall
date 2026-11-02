import Foundation

/// A shell command Claude Code is running for the session: a foreground command, one moved to the background (Ctrl+B),
/// a `run_in_background` command, or a Monitor. Mirrors the CLI's `task_*` events (docs/CLAUDE_CODE_PROTOCOL.md).
struct BackgroundTask: Identifiable, Equatable {
    enum Status: Equatable { case running, completed, stopped, failed }

    let id: String                 // the CLI's task_id
    var runID = ""
    var toolUseID = ""             // the Bash/Monitor call that started it; needed to move it to the background
    var title: String
    var isBackgrounded: Bool
    var status: Status = .running
    var startedAt = Date()
    var endedAt: Date?
    var outputFile: String?

    var isRunning: Bool { status == .running }
    /// A foreground command Claude is waiting on; the only kind that can be moved to the background.
    var canBackground: Bool { isRunning && !isBackgrounded && !toolUseID.isEmpty }

    static func status(forCLI s: String?) -> Status? {
        switch s {
        case "completed": .completed
        case "killed", "stopped", "cancelled", "canceled": .stopped
        case "failed", "error": .failed
        case "running", "pending": .running
        default: nil
        }
    }
}

/// A `/btw` question and its answer. Side questions never enter the main conversation.
struct SideQA: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var answer: String?
    var error: String?
    var isPending: Bool { answer == nil && error == nil }
}

extension Conversation {
    /// How many finished tasks to keep on screen, newest first.
    static let finishedTasksKept = 6

    // MARK: Task events

    /// Called for every event. Only `local_bash` tasks (commands and monitors) are tracked here; sub-agents have their own view.
    func trackTasks(_ e: [String: Any]) {
        guard e["type"] as? String == "system", let sub = e["subtype"] as? String else { return }
        switch sub {
        case "task_started":
            guard e["task_type"] as? String == "local_bash", let id = e["task_id"] as? String else { return }
            var t = BackgroundTask(id: id, title: (e["description"] as? String) ?? "Command",
                                   isBackgrounded: e["is_backgrounded"] as? Bool ?? false)
            t.runID = e["run_id"] as? String ?? ""
            t.toolUseID = e["tool_use_id"] as? String ?? ""
            if let i = tasks.firstIndex(where: { $0.id == id }) { t.startedAt = tasks[i].startedAt; tasks[i] = t } else { tasks.append(t) }
            pruneTasks()
        case "task_updated":
            guard let id = e["task_id"] as? String, let i = tasks.firstIndex(where: { $0.id == id }),
                  let patch = e["patch"] as? [String: Any] else { return }
            if let b = patch["is_backgrounded"] as? Bool { tasks[i].isBackgrounded = b }
            if let s = BackgroundTask.status(forCLI: patch["status"] as? String) {
                tasks[i].status = s
                if s != .running { tasks[i].endedAt = Self.date(fromMillis: patch["end_time"]) ?? Date() }
            }
            pruneTasks()
        case "task_notification":
            guard let id = e["task_id"] as? String, let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            if let s = BackgroundTask.status(forCLI: e["status"] as? String), s != .running {
                tasks[i].status = s
                if tasks[i].endedAt == nil { tasks[i].endedAt = Date() }
            }
            if let f = e["output_file"] as? String, !f.isEmpty { tasks[i].outputFile = f }
            pruneTasks()
        case "background_tasks_changed":
            // The CLI's list of live *backgrounded* tasks. One we think is backgrounded but that has left the list has ended.
            let live = Set((e["tasks"] as? [[String: Any]] ?? []).compactMap { $0["task_id"] as? String })
            for i in tasks.indices where tasks[i].isRunning && tasks[i].isBackgrounded && !live.contains(tasks[i].id) {
                tasks[i].status = .completed; tasks[i].endedAt = Date()
            }
            pruneTasks()
        default: break
        }
    }

    private static func date(fromMillis v: Any?) -> Date? {
        guard let ms = (v as? Double) ?? (v as? Int).map(Double.init), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private func pruneTasks() {
        let finished = tasks.enumerated().filter { !$0.element.isRunning }
        guard finished.count > Self.finishedTasksKept else { return }
        // Oldest first; ties (same instant) fall back to the order they were added, so the result is deterministic.
        let oldest = finished.sorted { ($0.element.endedAt ?? .distantPast, $0.offset) < ($1.element.endedAt ?? .distantPast, $1.offset) }
        let drop = Set(oldest.prefix(finished.count - Self.finishedTasksKept).map { $0.element.id })
        tasks.removeAll { drop.contains($0.id) }
    }

    /// The process is gone, and so is everything it was running.
    func endAllTasks() {
        for i in tasks.indices where tasks[i].isRunning { tasks[i].status = .stopped; tasks[i].endedAt = Date() }
    }

    var runningTasks: [BackgroundTask] { tasks.filter(\.isRunning) }
    var foregroundTasks: [BackgroundTask] { tasks.filter(\.canBackground) }

    // MARK: Task controls

    func stopTask(_ id: String) { runner?.request("stop_task", ["task_id": id]) }

    /// Ctrl+B: hand every foreground command back to Claude as a background task so the turn can carry on.
    func backgroundForeground() {
        for t in foregroundTasks { runner?.request("background_tasks", ["tool_use_id": t.toolUseID]) }
    }

    /// Live output of a running task, or, once it has finished, the tail of its output file.
    func taskOutput(_ t: BackgroundTask, completion: @escaping (String?) -> Void) {
        if t.isRunning, let r = runner, r.isAlive {
            r.request("get_task_output", ["task_id": t.id]) { body in completion(body?["output"] as? String) }
        } else if let f = t.outputFile {
            completion(Self.tail(ofFile: f))
        } else { completion(nil) }
    }

    nonisolated static func tail(ofFile path: String, maxBytes: Int = 20_000) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        guard let d = try? h.readToEnd() else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: /btw

    /// `/btw what's the ETA?` → "what's the ETA?". A bare `/btw` → "". Anything else → nil.
    nonisolated static func sideQuestion(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased() == "/btw" || t.lowercased().hasPrefix("/btw ") || t.lowercased().hasPrefix("/btw\n") else { return nil }
        return String(t.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ask Claude a quick question without interrupting the main conversation. Works while a turn is running: the
    /// CLI answers on the side and the answer never enters the transcript.
    func askSide(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let item = SideQA(question: q)
        let history = sideQA.compactMap { a in a.answer.map { ["question": a.question, "response": $0] } }.suffix(6)
        sideQA.append(item)
        do { if runner?.isAlive != true { try startRunner() } }
        catch { finishSide(item.id, answer: nil, error: error.localizedDescription); return }
        runner?.request("side_question", ["question": q, "history": Array(history)]) { [weak self] body in
            if let a = body?["response"] as? String { self?.finishSide(item.id, answer: a, error: nil) }
            else { self?.finishSide(item.id, answer: nil, error: "Couldn't answer. This version of Claude Code may not support /btw.") }
        }
        Task { @MainActor [weak self] in          // never leave a spinner up forever (a crashed CLI never replies)
            try? await Task.sleep(for: .seconds(90))
            self?.finishSide(item.id, answer: nil, error: "No answer came back.")
        }
    }

    private func finishSide(_ id: UUID, answer: String?, error: String?) {
        guard let i = sideQA.firstIndex(where: { $0.id == id }), sideQA[i].isPending else { return }
        sideQA[i].answer = answer; sideQA[i].error = error
    }

    func dismissSide(_ id: UUID) { sideQA.removeAll { $0.id == id } }
    func clearSide() { sideQA.removeAll() }
}
