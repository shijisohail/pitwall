import SwiftUI

/// A persistent "this session is running" strip above the composer: a pulsing dot, what Claude is doing right now, a live
/// timer, and a sweeping line. Without it the only sign of life, once a reply has started, is the stop button.
struct RunningBar: View {
    @Bindable var conversation: Conversation
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private var waiting: Bool { !conversation.approvals.isEmpty }
    private var color: Color { waiting ? HTB.amber : HTB.green }

    private var extras: String {
        var p: [String] = []
        if settings.showAgents, conversation.agentsWorking > 0 { p.append("\(conversation.agentsWorking) agent\(conversation.agentsWorking == 1 ? "" : "s")") }
        if !conversation.queue.isEmpty { p.append("\(conversation.queue.count) queued") }
        return p.joined(separator: " · ")
    }

    var body: some View {
        if conversation.isRunning {
            HStack(spacing: 10) {
                PulseDot(color: color, pulsing: true)
                Text(conversation.activityText).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if !extras.isEmpty { Text(extras).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 8)
                if let t = conversation.turnStart { Text(t, style: .timer).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottom) { sweepLine }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.35)))
            .onAppear { sweep = true }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session running: \(conversation.activityText)")
            .transition(.opacity)
        }
    }

    /// A short bright segment sliding along the bottom edge. Static (full, dim) when Reduce Motion is on.
    private var sweepLine: some View {
        GeometryReader { g in
            Capsule().fill(LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: reduceMotion ? g.size.width : g.size.width * 0.3, height: 2)
                .opacity(reduceMotion ? 0.35 : 1)
                .offset(x: reduceMotion ? 0 : (sweep ? g.size.width : -g.size.width * 0.3))
                .animation(reduceMotion ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false), value: sweep)
        }
        .frame(height: 2).allowsHitTesting(false)
    }
}
