// Draws docs/assets/social-preview.png (1280x640, GitHub's social preview size).
//   swiftc -sdk "$(xcrun --show-sdk-path)" Scripts/make-social-preview.swift -o /tmp/make-social && /tmp/make-social docs/assets/social-preview.png
// (On a bare Command Line Tools install, pass -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk instead.)
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "social-preview.png"
let W = 1280, H = 640
let lime = NSColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 1)
let amber = NSColor(red: 1.0, green: 0.69, blue: 0.0, alpha: 1)
let blue = NSColor(red: 0.36, green: 0.70, blue: 1.0, alpha: 1)
let panel = NSColor(red: 0.067, green: 0.086, blue: 0.118, alpha: 1)
let border = NSColor(red: 0.16, green: 0.20, blue: 0.27, alpha: 1)
let mono = "Menlo-Bold"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// ground, glows, dot grid
ctx.setFillColor(NSColor(red: 0.035, green: 0.047, blue: 0.065, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
func glow(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: [c.withAlphaComponent(a).cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
glow(lime, 1120, 600, 760, 0.17); glow(blue, 60, 20, 640, 0.12)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
for gx in stride(from: 26, to: W, by: 34) { for gy in stride(from: 26, to: H, by: 34) { ctx.fillEllipse(in: CGRect(x: CGFloat(gx), y: CGFloat(gy), width: 2.4, height: 2.4)) } }
ctx.setStrokeColor(border.cgColor); ctx.setLineWidth(2); ctx.stroke(CGRect(x: 1, y: 1, width: W - 2, height: H - 2))

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color, .kern: kern])
}

// app icon
if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") {
    icon.draw(in: NSRect(x: 64, y: 400, width: 168, height: 168))
}

// words
text("PITWALL", 64, 268, font: NSFont(name: mono, size: 124)!, color: lime, kern: 6)
ctx.setFillColor(lime.cgColor); ctx.fill(CGRect(x: 68, y: 246, width: 92, height: 7))
text("A native macOS app for Claude Code", 64, 178, font: NSFont.systemFont(ofSize: 35, weight: .semibold), color: NSColor(white: 0.93, alpha: 1))
text("Many sessions in tabs  ·  one-click approvals  ·  every change, live", 64, 126, font: NSFont(name: "Menlo", size: 20)!, color: NSColor(white: 0.62, alpha: 1))
// footer pill
let pill = NSBezierPath(roundedRect: NSRect(x: 64, y: 44, width: 478, height: 46), xRadius: 10, yRadius: 10)
panel.setFill(); pill.fill(); lime.withAlphaComponent(0.55).setStroke(); pill.lineWidth = 1.5; pill.stroke()
text("★  github.com/shijisohail/pitwall", 86, 57, font: NSFont(name: mono, size: 22)!, color: lime)
text("MIT  ·  open source", 566, 57, font: NSFont(name: "Menlo", size: 21)!, color: NSColor(white: 0.55, alpha: 1))

// the board, as a sketch (right side)
func card(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, tint: NSColor? = nil, lines: Int = 2, bar: CGFloat? = nil, buttons: Bool = false) {
    let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 10, yRadius: 10)
    (tint?.withAlphaComponent(0.09) ?? panel).setFill(); r.fill()
    (tint?.withAlphaComponent(0.65) ?? border).setStroke(); r.lineWidth = 1.5; r.stroke()
    NSColor(white: 0.93, alpha: 0.85).setFill(); NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + h - 26, width: w * 0.55, height: 9), xRadius: 4, yRadius: 4).fill()
    if lines > 0 {
        NSColor.black.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + h - 26 - 12 - CGFloat(lines) * 15, width: w - 28, height: CGFloat(lines) * 15 + 4), xRadius: 6, yRadius: 6).fill()
    }
    if let bar { border.setFill(); NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 14, width: w - 28, height: 6), xRadius: 3, yRadius: 3).fill()
        lime.setFill(); NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 14, width: (w - 28) * bar, height: 6), xRadius: 3, yRadius: 3).fill() }
    if buttons {
        lime.setFill(); NSBezierPath(roundedRect: NSRect(x: x + 12, y: y + 14, width: 50, height: 28), xRadius: 7, yRadius: 7).fill()
        NSColor(white: 0.13, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: x + 68, y: y + 14, width: 34, height: 28), xRadius: 7, yRadius: 7).fill()
        NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.7).setStroke(); let d = NSBezierPath(roundedRect: NSRect(x: x + 108, y: y + 14, width: 28, height: 28), xRadius: 7, yRadius: 7); d.lineWidth = 1.5; d.stroke()
    }
}
let colX: [CGFloat] = [748, 906, 1064], cw: CGFloat = 148
text("WORKING", colX[0], 548, font: NSFont(name: mono, size: 15)!, color: lime, kern: 1.5)
text("NEEDS YOU", colX[1], 548, font: NSFont(name: mono, size: 15)!, color: amber, kern: 1.5)
text("DONE", colX[2], 548, font: NSFont(name: mono, size: 15)!, color: NSColor(white: 0.55, alpha: 1), kern: 1.5)
card(colX[0], 400, cw, 128, lines: 2, bar: 0.62); card(colX[0], 270, cw, 116, lines: 1, bar: 0.25); card(colX[0], 150, cw, 106, lines: 1, bar: 0.8)
card(colX[1], 386, cw, 142, tint: amber, lines: 2, buttons: true); card(colX[1], 250, cw, 122, tint: amber, lines: 1, buttons: true)
card(colX[2], 440, cw, 88, lines: 0); card(colX[2], 336, cw, 88, lines: 0); card(colX[2], 232, cw, 88, lines: 0); card(colX[2], 128, cw, 88, lines: 0)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(W)x\(H))")
