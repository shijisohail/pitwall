import SwiftUI

/// Hack-The-Box-inspired palette: near-black ground, lime accent, cool secondary. Dark only.
enum HTB {
    static let green = Color(red: 0.62, green: 0.94, blue: 0.0)      // #9FEF00
    static let cyan = Color(red: 0.36, green: 0.70, blue: 1.0)       // #5CB2FF
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.0)       // #FFAF00
    static let red = Color(red: 1.0, green: 0.30, blue: 0.30)        // #FF4D4D
    static let bg = Color(red: 0.035, green: 0.047, blue: 0.065)     // #090C11
    static let panel = Color(red: 0.067, green: 0.086, blue: 0.118)  // #11161E
    static let raised = Color(red: 0.090, green: 0.114, blue: 0.153) // #171D27
    static let border = Color(red: 0.16, green: 0.20, blue: 0.27)    // #293345
}

/// Behind-window blur, so the desktop shows through the window, darkened to the theme. Also makes the window non-opaque.
struct WindowGlass: NSViewRepresentable {
    final class Blur: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
        }
    }
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = Blur()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// The window background: the desktop blurred and tinted near-black, with two faint glows and a dot grid.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                HTB.bg
            } else {
                WindowGlass()
                HTB.bg.opacity(AppSettings.shared.windowTint)       // Settings ▸ Appearance ▸ Glassiness
            }
            // Only the two soft glows move, and slowly, so a few frames a second is plenty.
            // The dot grid sits outside the timeline so it is drawn once, not every frame.
            if reduceMotion || !AppSettings.shared.animatedBackground {
                glows(0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 5)) { glows($0.date.timeIntervalSinceReferenceDate) }
            }
            DotGrid().drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glows(_ t: Double) -> some View {
        ZStack {
            RadialGradient(colors: [HTB.green.opacity(0.09), .clear],
                           center: UnitPoint(x: 0.86 + 0.04 * sin(t * 0.15), y: 0), startRadius: 0, endRadius: 560)
            RadialGradient(colors: [HTB.cyan.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.04, y: 1 + 0.04 * cos(t * 0.12)), startRadius: 0, endRadius: 520)
        }
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 26
            var y: CGFloat = 13
            while y < size.height {
                var x: CGFloat = 13
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.05)))
                    x += step
                }
                y += step
            }
        }
    }
}

/// Scrolls its content once it is taller than `maxHeight`, and is exactly as tall as the content when it is not.
/// For anything that sits in the chat's bottom bar, which can't grow without pushing the prompt box off-screen.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
    }
}

func relativeTime(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: d, relativeTo: Date())
}

extension View {
    /// A dark glass panel with a hairline border; `tint` marks it as needing attention.
    func panel<S: InsettableShape>(_ shape: S, tint: Color? = nil, border: Color? = nil) -> some View {
        background(shape.fill(HTB.panel.opacity(AppSettings.shared.cardFill)))
            .background(shape.fill(tint ?? .clear))
            .glassEffect(.regular.tint(HTB.bg.opacity(0.7)), in: shape)
            .overlay(shape.strokeBorder(border.map { AnyShapeStyle($0) }
                                        ?? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.14), HTB.border],
                                                                        startPoint: .top, endPoint: .center)),
                                        lineWidth: 1))
    }

    func glassCard(_ radius: CGFloat = 16, tint: Color? = nil) -> some View {
        panel(RoundedRectangle(cornerRadius: min(radius, 12), style: .continuous), tint: tint,
              border: tint == nil ? nil : HTB.amber.opacity(0.55))
    }
}

// MARK: Buttons

struct HTBPrimary: ButtonStyle {
    var circle = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        configuration.label
            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.horizontal, circle ? 0 : 14).padding(.vertical, circle ? 0 : 7)
            .background(shape.fill(HTB.green.opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.28)))
            .shadow(color: HTB.green.opacity(enabled ? 0.3 : 0), radius: 8)
    }
}

struct HTBSecondary: ButtonStyle {
    var circle = false
    var color: Color = .primary
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(color.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, circle ? 0 : 12).padding(.vertical, circle ? 0 : 6)
            .frame(minWidth: circle ? 30 : nil, minHeight: circle ? 30 : nil)
            .background(shape.fill(configuration.isPressed ? HTB.raised : HTB.panel.opacity(AppSettings.shared.cardFill)))
            .glassEffect(.regular.tint(HTB.bg.opacity(0.7)), in: shape)
            .overlay(shape.stroke(color == .primary ? HTB.border : color.opacity(0.55), lineWidth: 1))
    }
}

struct HTBChip: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: on ? .bold : .regular, design: .monospaced))
            .foregroundStyle(on ? HTB.green : Color.secondary)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? HTB.green.opacity(0.12) : (configuration.isPressed ? HTB.raised : HTB.panel.opacity(AppSettings.shared.cardFill))))
            .glassEffect(.regular.tint(HTB.bg.opacity(0.7)), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? HTB.green.opacity(0.6) : HTB.border, lineWidth: 1))
    }
}
