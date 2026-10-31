// Draws Resources/AppIcon.icns' source artwork.
//   SDK=$(xcrun --show-sdk-path)    # on a bare CLT install use /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
//   swiftc -sdk "$SDK" Scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources/AppIcon.iconset
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func master() -> NSBitmapImageRep {
    let s = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let lime = CGColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 1)

    // macOS icon grid: 824pt rounded square centred in the 1024pt canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.5))
    ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.035, green: 0.047, blue: 0.065, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.075, green: 0.10, blue: 0.135, alpha: 1),
                                                    CGColor(red: 0.03, green: 0.04, blue: 0.055, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 0.22), CGColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 430, options: [])
    // faint dot grid, like the app background
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.05))
    for gx in stride(from: 130, to: 920, by: 46) { for gy in stride(from: 130, to: 920, by: 46) { ctx.fillEllipse(in: CGRect(x: gx, y: gy, width: 3, height: 3)) } }
    ctx.restoreGState()

    // hairline border
    ctx.addPath(path); ctx.setStrokeColor(CGColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 0.35)); ctx.setLineWidth(5); ctx.strokePath()

    // a four-point spark with concave sides
    func spark(center c: CGPoint, r: CGFloat, pinch: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * pinch, y: c.y + r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * pinch, y: c.y - r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * pinch, y: c.y - r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * pinch, y: c.y + r * pinch))
        p.closeSubpath(); return p
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 0.62, green: 0.94, blue: 0.0, alpha: 0.85))
    ctx.addPath(spark(center: CGPoint(x: 500, y: 530), r: 270, pinch: 0.16)); ctx.setFillColor(lime); ctx.fillPath()
    ctx.addPath(spark(center: CGPoint(x: 735, y: 745), r: 92, pinch: 0.18)); ctx.setFillColor(lime); ctx.fillPath()
    ctx.restoreGState()

    // terminal caret under the spark
    let caret = CGMutablePath()
    caret.move(to: CGPoint(x: 282, y: 272)); caret.addLine(to: CGPoint(x: 352, y: 232)); caret.addLine(to: CGPoint(x: 282, y: 192))
    ctx.addPath(caret); ctx.setStrokeColor(lime); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.setFillColor(lime); ctx.fill(CGRect(x: 390, y: 200, width: 120, height: 22))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let m = master()
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                              ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    NSGraphicsContext.current?.imageInterpolation = .high
    m.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("wrote \(sizes.count) sizes to \(out)")
