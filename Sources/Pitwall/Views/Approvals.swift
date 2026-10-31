import SwiftUI

struct ApprovalStack: View {
    @Bindable var conversation: Conversation

    var body: some View {
        VStack(spacing: 10) {
            ForEach(conversation.approvals) { a in
                switch a.kind {
                case .tool: ToolApprovalCard(conversation: conversation, a: a)
                case .question: QuestionCard(conversation: conversation, a: a)
                case .plan: PlanCard(conversation: conversation, a: a)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: conversation.approvals.count)
    }
}

private extension View {
    func approvalChrome(_ tint: Color) -> some View {
        padding(16).panel(RoundedRectangle(cornerRadius: 12), tint: tint.opacity(0.08), border: tint.opacity(0.6))
    }
}

func suggestionLabel(_ s: [String: Any]) -> String {
    switch s["type"] as? String {
    case "setMode":
        return (s["mode"] as? String) == "acceptEdits" ? "Allow all edits this session" : "Switch mode"
    case "addRules":
        let r = (s["rules"] as? [[String: Any]])?.first
        if let c = r?["ruleContent"] as? String { return "Always allow `\(c.prefix(36))`" }
        return "Always allow \(r?["toolName"] as? String ?? "this")"
    default: return "Always allow"
    }
}

struct ToolApprovalCard: View {
    @Bindable var conversation: Conversation
    let a: Approval
    @State private var feedback = ""

    private var tool: Block {
        var b = Block(kind: .tool); b.toolName = a.tool
        if let d = try? JSONSerialization.data(withJSONObject: a.input) { b.inputJSON = String(decoding: d, as: UTF8.self) }
        return b
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: tool.toolIcon.name).foregroundStyle(tool.toolIcon.color)
                Text("Claude wants to use **\(a.tool)**")
                Spacer()
                if let r = a.reason { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            preview
                .background(.black.opacity(0.26)).clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Button("Allow") { conversation.allow(a) }.buttonStyle(HTBPrimary())
                ForEach(Array(a.suggestions.enumerated()), id: \.offset) { _, s in
                    Button(LocalizedStringKey(suggestionLabel(s))) { conversation.allow(a, remember: s) }.buttonStyle(HTBSecondary())
                }
                Spacer(minLength: 8)
                TextField("Or tell Claude what to do instead…", text: $feedback)
                    .textFieldStyle(.plain).font(.callout).frame(maxWidth: 240)
                    .onSubmit { conversation.deny(a, message: feedback) }
                Button("Deny") { conversation.deny(a, message: feedback) }.buttonStyle(HTBSecondary(color: HTB.red))
            }
            .controlSize(.regular)
        }
        .approvalChrome(.orange)
    }

    @ViewBuilder private var preview: some View {
        let i = a.input
        switch a.tool {
        case "Bash": OutputBox(text: "$ " + (i["command"] as? String ?? ""), tint: .orange)
        case "Edit": DiffView(old: i["old_string"] as? String ?? "", new: i["new_string"] as? String ?? "")
        case "Write":
            VStack(alignment: .leading, spacing: 0) {
                Text((i["file_path"] as? String ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).padding([.horizontal, .top], 12)
                DiffView(old: "", new: i["content"] as? String ?? "")
            }
        case "MultiEdit":
            VStack(spacing: 0) {
                ForEach(Array((i["edits"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, e in
                    DiffView(old: e["old_string"] as? String ?? "", new: e["new_string"] as? String ?? "")
                }
            }
        default:
            OutputBox(text: tool.inputJSON.isEmpty ? (a.detail ?? "") : prettyJSON(tool.inputJSON), tint: nil)
        }
    }
}

func prettyJSON(_ json: String) -> String {
    guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d),
          let p = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return json }
    return String(decoding: p, as: UTF8.self)
}

struct QuestionCard: View {
    @Bindable var conversation: Conversation
    let a: Approval
    @State private var picks: [Int: Set<String>] = [:]
    @State private var other: [Int: String] = [:]

    private var questions: [[String: Any]] { a.input["questions"] as? [[String: Any]] ?? [] }

    private func answered(_ i: Int) -> Bool { !(picks[i]?.isEmpty ?? true) || !(other[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Claude has a question", systemImage: "questionmark.bubble").fontWeight(.semibold)
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                let multi = q["multiSelect"] as? Bool ?? false
                let options = q["options"] as? [[String: Any]] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let h = q["header"] as? String {
                            Text(h).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        Text(q["question"] as? String ?? "")
                    }
                    ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                        let label = o["label"] as? String ?? ""
                        let on = picks[i]?.contains(label) ?? false
                        Button {
                            if multi { if on { picks[i]?.remove(label) } else { picks[i, default: []].insert(label) } }
                            else { picks[i] = [label]; other[i] = "" }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: multi ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                                    .foregroundStyle(on ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(label).fontWeight(.medium)
                                    if let d = o["description"] as? String, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).contentShape(Rectangle())
                            .background(on ? Color.accentColor.opacity(0.18) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    TextField("Other…", text: Binding(get: { other[i] ?? "" }, set: { other[i] = $0; if !multi, !$0.isEmpty { picks[i] = [] } }))
                        .textFieldStyle(.plain).padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            HStack {
                Button("Skip") { conversation.deny(a, message: "The user skipped this question.") }.buttonStyle(HTBSecondary())
                Spacer()
                Button("Submit") { submit() }.buttonStyle(HTBPrimary())
                    .disabled(!questions.indices.allSatisfy(answered))
            }
        }
        .approvalChrome(.yellow)
    }

    private func submit() {
        var answers: [String: Any] = [:]
        for (i, q) in questions.enumerated() {
            let multi = q["multiSelect"] as? Bool ?? false
            let order = (q["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            var vals = order.filter { picks[i]?.contains($0) ?? false }
            let o = (other[i] ?? "").trimmingCharacters(in: .whitespaces)
            if !o.isEmpty { multi ? vals.append(o) : (vals = [o]) }
            answers[q["question"] as? String ?? ""] = multi ? vals.joined(separator: ", ") : (vals.first ?? "")
        }
        conversation.allow(a, input: ["questions": questions, "answers": answers])
    }
}

struct PlanCard: View {
    @Bindable var conversation: Conversation
    let a: Approval
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Claude's plan", systemImage: "map").fontWeight(.semibold)
            ScrollView { MarkdownView(text: a.input["plan"] as? String ?? "").padding(14) }
                .frame(maxHeight: 300)
                .background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 8) {
                Button("Approve & auto-accept edits") {
                    conversation.allow(a, remember: ["type": "setMode", "mode": "acceptEdits", "destination": "session"])
                }.buttonStyle(HTBPrimary())
                Button("Approve, review each edit") {
                    conversation.allow(a); conversation.setPermissionSilently(.manual)
                }.buttonStyle(HTBSecondary())
                Spacer(minLength: 8)
                TextField("What should change?", text: $feedback).textFieldStyle(.plain).font(.callout).frame(maxWidth: 200)
                    .onSubmit(keepPlanning)
                Button("Keep planning", action: keepPlanning).buttonStyle(HTBSecondary(color: HTB.red))
            }
        }
        .approvalChrome(.mint)
    }

    private func keepPlanning() {
        conversation.deny(a, message: feedback.isEmpty ? "The user wants you to keep planning." : "The user wants changes to the plan: \(feedback)")
    }
}
