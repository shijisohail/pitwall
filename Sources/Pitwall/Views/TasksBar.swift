import SwiftUI

/// The shell commands Claude is running for this session: background commands, Monitors, and a command it is waiting on.
/// Each can be watched (live output), stopped, or, if Claude is waiting on it, moved to the background (⌘B).
struct TasksBar: View {
    @Bindable var conversation: Conversation

    private var running: Int { conversation.runningTasks.count }
    private var summary: String {
        let done = conversation.tasks.count - running
        var p: [String] = []
        if running > 0 { p.append("\(running) running") }
        if done > 0 { p.append("\(done) finished") }
        return p.joined(separator: " · ")
    }

    var body: some View {
        if !conversation.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if conversation.tasksExpanded {
                    Divider().opacity(0.4)
                    VStack(spacing: 0) {
                        ForEach(conversation.tasks) { t in
                            TaskRow(conversation: conversation, task: t)
                            if t.id != conversation.tasks.last?.id { Divider().opacity(0.25) }
                        }
                    }
                }
            }
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .transition(.opacity)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { conversation.tasksExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal").foregroundStyle(running > 0 ? HTB.green : .secondary)
                    Text("Tasks").font(.system(size: 12.5, weight: .semibold))
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                    Image(systemName: conversation.tasksExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !conversation.foregroundTasks.isEmpty {
                Button("Run in background") { conversation.backgroundForeground() }
                    .buttonStyle(HTBSecondary()).controlSize(.small).help("Let Claude carry on while this command keeps running (⌘B)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }
}

private struct TaskRow: View {
    @Bindable var conversation: Conversation
    let task: BackgroundTask
    @State private var showOutput = false
    @State private var output: String?

    private var color: Color {
        switch task.status { case .running: HTB.green; case .completed: .secondary; case .stopped: HTB.amber; case .failed: HTB.red }
    }
    private var statusText: String {
        switch task.status {
        case .running: task.isBackgrounded ? "background" : "foreground"
        case .completed: "done"; case .stopped: "stopped"; case .failed: "failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                PulseDot(color: color, pulsing: task.isRunning)
                Text(task.title).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text(statusText).font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if task.isRunning { Text(task.startedAt, style: .timer).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).monospacedDigit() }
                else if let e = task.endedAt { Text(Self.duration(e.timeIntervalSince(task.startedAt))).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary) }
                Button(showOutput ? "Hide output" : "Output") { showOutput.toggle() }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(HTB.cyan)
                if task.canBackground { Button("Background") { conversation.backgroundForeground() }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(HTB.cyan) }
                if task.isRunning { Button("Stop") { conversation.stopTask(task.id) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(HTB.red) }
                else if let f = task.outputFile {
                    Button("Open log") { Store.shared.openFile(f) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(HTB.cyan)
                }
            }
            if showOutput {
                Group {
                    if let o = output, !o.isEmpty { OutputBox(text: String(o.suffix(6_000)), tint: nil) }
                    else { Text(output == nil ? "Loading…" : "(no output yet)").font(.system(size: 12)).foregroundStyle(.tertiary) }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // Live output: poll while it is open and the task is running; one last read when it finishes.
        .task(id: "\(showOutput)-\(task.isRunning)") {
            guard showOutput else { return }
            repeat {
                conversation.taskOutput(task) { output = $0 ?? output }
                guard task.isRunning else { break }
                try? await Task.sleep(for: .seconds(1))
            } while !Task.isCancelled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(statusText)")
    }

    private static func duration(_ s: TimeInterval) -> String {
        s < 60 ? String(format: "%.0fs", max(s, 0)) : String(format: "%dm %02ds", Int(s) / 60, Int(s) % 60)
    }
}
