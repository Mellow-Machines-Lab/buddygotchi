// The app's icon, a placeholder until a designed one replaces it: Boop's
// face as the menu bar draws it, two tall eyes on the device's black
// glass, on the popover's warm paper, in macOS's rounded square.
// Draws every size an icon set needs, then iconutil packs them into one
// .icns:
//   swift internal/tools/appicon/appicon.swift app/Boop/AppIcon.icns [preview.png]
import AppKit

let args = CommandLine.arguments.dropFirst()
guard let out = args.first, out.hasSuffix(".icns") else {
    FileHandle.standardError.write(Data("usage: appicon.swift OUT.icns [PREVIEW.png]\n".utf8))
    exit(2)
}
let preview = args.dropFirst().first

func colour(_ hex: String) -> NSColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// The icon at `pixels` square, drawn on a 1024-point grid: Apple's
/// template puts the rounded square at 824 points, centred, with room
/// for its shadow.
func draw(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSAffineTransform().with { $0.scale(by: scale); $0.concat() }

    // The rounded square of warm paper, with a soft shadow under it.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    colour("#F3EDE3").setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: colour("#FFFDF9"), ending: colour("#EBE3D6"))!.draw(in: body, angle: -90)

    // The screen: the device's black glass, lit a little from the top.
    let screen = NSBezierPath(roundedRect: NSRect(x: 196, y: 196, width: 632, height: 632), xRadius: 132, yRadius: 132)
    NSGradient(starting: colour("#2A2620"), ending: colour("#000000"))!.draw(in: screen, angle: -90)

    // Two tall eyes in the device's oat, as wide as the gap between them,
    // as on the menu bar.
    colour("#E8DCC4").setFill()
    for x: CGFloat in [356, 564] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 430, width: 104, height: 170), xRadius: 52, yRadius: 52).fill()
    }
    // Coral cheeks, below and outside the eyes.
    colour("#F1787D").withAlphaComponent(0.85).setFill()
    for x: CGFloat in [286, 666] {
        NSBezierPath(ovalIn: NSRect(x: x, y: 382, width: 72, height: 44)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSAffineTransform {
    func with(_ body: (NSAffineTransform) -> Void) { body(self) }
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! png(draw(points)).write(to: set.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(draw(points * 2)).write(to: set.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", out]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: set)
guard iconutil.terminationStatus == 0 else { exit(1) }
if let preview { try! png(draw(1024)).write(to: URL(fileURLWithPath: preview)) }
print("appicon: wrote \(out)" + (preview.map { " and \($0)" } ?? ""))
