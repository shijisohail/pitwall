import SwiftUI

/// Dynamic workflows Claude is running or has just run: a script that fans work out to many agents in phases. Shows each
/// phase with its agents (what each is doing, tokens, time), lets you stop a run, and keeps the script and log reachable.
struct WorkflowsBar: View {
    @Bindable var conversation: Conversation

    var body: some View {
        if !conversation.workflows.isEmpty {
            VStack(spacing: 8) {
                ForEach(conversation.workflows) { w in WorkflowCard(conversation: conversation, workflow: w) }
            }
            .transition(.opacity)
        }
    }
}

private func workflowTint(_ s: WorkflowRun.Status) -> Color {
    switch s { case .running: HTB.green; case .completed: Color(red: 0.73, green: 0.50, blue: 1.0); case .stopped: HTB.amber; case .failed: HTB.red }
}

private func agentTint(_ s: WorkflowAgent.State) -> Color {
    switch s { case .running: HTB.green; case .done: .secondary; case .failed: HTB.red; case .stopped: HTB.amber }
}

private func compactTokens(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }

private func clockText(_ s: TimeInterval) -> String {
    let t = max(Int(s), 0); return t < 60 ? "\(t)s" : "\(t / 60)m \(t % 60)s"
}

private struct WorkflowCard: View {
    @Bindable var conversation: Conversation
    let workflow: WorkflowRun
    @State private var open = true
    @State private var showScript = false
    @State private var selectedAgent: String?

    private var statusWord: String {
        switch workflow.status { case .running: "running"; case .completed: "done"; case .stopped: "stopped"; case .failed: "failed" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if open {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 10) {
                    if workflow.isRunning, !workflow.activity.isEmpty {
                        Text(workflow.activity).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if workflow.phases.isEmpty && workflow.agents.isEmpty {
                        Text("Starting…").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    ForEach(workflow.phases) { phase in phaseSection(phase) }
                    if showScript { scriptBox }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(workflow.isRunning ? HTB.green.opacity(0.35) : .white.opacity(0.14)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workflow \(workflow.name), \(statusWord). \(workflow.progressLine)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    PulseDot(color: workflowTint(workflow.status), pulsing: workflow.isRunning)
                    Text("Workflow").font(.system(size: 12.5, weight: .semibold))
                    Text(workflow.name).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Text(workflow.isRunning ? workflow.progressLine : "\(statusWord)" + (workflow.progressLine.isEmpty ? "" : " · \(workflow.progressLine)"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if workflow.isRunning {
                Text(workflow.startedAt, style: .timer).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).monospacedDigit()
                Button("Stop") { conversation.stopWorkflow(workflow.id) }.buttonStyle(.plain)
                    .font(.system(size: 11.5)).foregroundStyle(HTB.red).help("Stop the workflow and all of its agents")
            } else {
                if let e = workflow.endedAt {
                    Text(clockText(e.timeIntervalSince(workflow.startedAt))).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if let f = workflow.outputFile { Button("Open log") { Store.shared.openFile(f) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(HTB.cyan) }
                Button { conversation.dismissWorkflow(workflow.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).frame(width: 22, height: 22).contentShape(Rectangle())
                    .help("Dismiss").accessibilityLabel("Dismiss workflow")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func phaseSection(_ phase: WorkflowPhase) -> some View {
        let agents = workflow.agents(in: phase)
        let done = agents.filter(\.isFinished).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(phase.index)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 16, height: 16).background(.white.opacity(0.12), in: Circle())
                Text(phase.title).font(.system(size: 12, weight: .semibold))
                if !agents.isEmpty { Text("\(done)/\(agents.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if phase.index == 1, !workflow.script.isEmpty {
                    Button(showScript ? "Hide script" : "Script") { showScript.toggle() }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(HTB.cyan)
                }
            }
            if agents.isEmpty {
                Text("Waiting").font(.system(size: 11.5)).foregroundStyle(.tertiary).padding(.leading, 22)
            } else {
                VStack(spacing: 4) {
                    ForEach(agents) { a in agentRow(a) }
                }.padding(.leading, 22)
            }
        }
    }

    private func agentRow(_ a: WorkflowAgent) -> some View {
        let selected = selectedAgent == a.id
        return VStack(alignment: .leading, spacing: 5) {
            Button { selectedAgent = selected ? nil : a.id } label: {
                HStack(spacing: 8) {
                    PulseDot(color: agentTint(a.state), pulsing: a.state == .running)
                    Text(a.label).font(.system(size: 12)).lineLimit(1)
                    if a.attempt > 1 { Text("try \(a.attempt)").font(.system(size: 10.5)).foregroundStyle(HTB.amber) }
                    Text(a.state == .running ? [a.tool, a.toolSummary].filter { !$0.isEmpty }.joined(separator: " ") : stateWord(a))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    if a.tokens > 0 { Text("\(compactTokens(a.tokens)) tok").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary) }
                    if a.durationMS > 0 { Text(clockText(Double(a.durationMS) / 1000)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if selected {
                VStack(alignment: .leading, spacing: 5) {
                    if !a.model.isEmpty { Text(a.model).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary) }
                    if !a.prompt.isEmpty { section("Task", a.prompt) }
                    if !a.error.isEmpty { section("Error", a.error) }
                    if !a.result.isEmpty { section("Result", a.result) }
                }.padding(.leading, 16).padding(.bottom, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.label), \(stateWord(a))")
    }

    private func stateWord(_ a: WorkflowAgent) -> String {
        switch a.state { case .running: "running"; case .done: "done"; case .failed: "failed"; case .stopped: "stopped" }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
        }
    }

    private var scriptBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Script").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                Spacer()
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(workflow.script, forType: .string) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(HTB.cyan)
            }
            ScrollView { Text(workflow.script).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 180)
        }
        .padding(8).background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
    }
}
