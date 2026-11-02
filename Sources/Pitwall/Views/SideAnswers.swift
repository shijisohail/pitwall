import SwiftUI

/// `/btw` questions and their answers, above the composer. They are answered on the side, even while Claude is busy,
/// and never become part of the conversation.
struct SideAnswers: View {
    @Bindable var conversation: Conversation

    var body: some View {
        if !conversation.sideQA.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(conversation.sideQA.suffix(3)) { qa in
                    SideAnswerRow(qa: qa) { conversation.dismissSide(qa.id) }
                }
            }
            .transition(.opacity)
        }
    }
}

private struct SideAnswerRow: View {
    let qa: SideQA
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("btw").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(HTB.bg)
                .padding(.horizontal, 7).padding(.vertical, 2).background(HTB.cyan, in: Capsule())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(qa.question).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                if let a = qa.answer {
                    MarkdownView(text: a).font(.system(size: 13.5))
                } else if let e = qa.error {
                    Text(e).font(.system(size: 12.5)).foregroundStyle(HTB.red)
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 12.5)).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.tertiary).help("Dismiss").accessibilityLabel("Dismiss side answer")
        }
        .padding(12)
        .background(HTB.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HTB.cyan.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}
