import AppKit
import BoopKit
import SwiftUI

/// Which look the little face shows. The Mac never plays Boop's reactions;
/// this is just enough of the device's face that the popover and the menu
/// bar read as the same creature.
enum FaceMood: Hashable {
    case asleep, idle, working, needsYou, happy
    /// Boop couldn't start: the menu bar's crossed eyes, so it never passes
    /// for napping.
    case stopped

    init(_ status: Runtime.Status?) {
        guard let status else {
            self = .asleep
            return
        }
        let s = status.snapshot
        if s.attn != nil {
            self = .needsYou
        } else {
            switch s.base {
            case "working": self = .working
            case "idle": self = .idle
            default: self = .asleep
            }
        }
    }
}

/// Boop's face on a small black-glass tile: the face of the device's design
/// for Boop's mood and look (FaceDesigns, which facegen writes from the same
/// designs as the device's), at rest, without the props. It blinks now and
/// then, and cross-fades into a new face when the mood or the look changes.
struct BoopFace: View {
    var mood: FaceMood
    /// Boop's mood, which picks the set of designs.
    var design: String = MoodOutput.initial
    var size: CGFloat

    @ViewState private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotion) private var still
    @Environment(\.displayScale) private var displayScale

    /// The board's dissolve between pictures: rig::kFadeMs, on its
    /// smoothstep ease, which this curve is exactly.
    private static let fade = Animation.timingCurve(1.0 / 3, 0, 2.0 / 3, 1, duration: 0.2)

    /// The design the tile shows. Asleep and setup's previews are the
    /// pack's startup mood's: the engine names no mood of its own.
    private var key: String {
        let startup = CharacterPack.active.startupMood
        return switch mood {
        case .asleep: "\(startup)/asleep"
        case .stopped: "stopped"
        case .idle: "\(design)/idle"
        case .working: "\(design)/working"
        case .needsYou: "\(design)/needs_you"
        case .happy: "\(startup)/idle"
        }
    }

    /// The key's face, else its mood's idle one, else the startup mood's,
    /// else any: a pack's faces.json may not have every look.
    private static func face(_ key: String) -> (open: [FaceRect], shut: [FaceRect]) {
        let mood = key.split(separator: "/").first.map(String.init) ?? ""
        return faces[key] ?? faces["\(mood)/idle"] ?? faces["\(CharacterPack.active.startupMood)/idle"]
            ?? faces.sorted { $0.key < $1.key }.first?.value ?? (open: [], shut: [])
    }

    var body: some View {
        let key = key
        let face = Self.face(key)
        let rects = blink ? face.shut : face.open
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.glass)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(mood == .needsYou ? Theme.amber : Theme.hairlineStrong.opacity(0.6),
                              lineWidth: mood == .needsYou ? max(1.5, size * 0.04) : 1)
            // The old face and the new one add, as the board's dither mixes
            // them: a pixel both light stays lit through the fade.
            ZStack {
                Canvas { context, canvas in
                    // Boop couldn't start, or the pack has no still faces:
                    // the menu bar's eyes, so the tile is never blank.
                    if mood == .stopped || Self.faces.isEmpty {
                        for (path, stroke) in Self.eyes(mood, shut: blink, in: canvas) {
                            if stroke {
                                context.stroke(path, with: .color(Self.eyeInk),
                                               style: StrokeStyle(lineWidth: canvas.width * 0.05, lineCap: .round))
                            } else {
                                context.fill(path, with: .color(mood == .asleep ? Self.eyeInk.opacity(0.7) : Self.eyeInk))
                            }
                        }
                        return
                    }
                    for (colour, path) in Self.paths(rects, in: canvas, scale: displayScale) {
                        context.fill(path, with: .color(mood == .asleep ? colour.opacity(0.7) : colour))
                    }
                }
                .id(key)
                .transition(.opacity)
                .blendMode(.plusLighter)
            }
            .compositingGroup()
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : Self.fade, value: key)
        // Either motion setting changes the id, so an existing blink
        // loop stops as soon as motion is turned off. A new face restarts
        // it, its first blink seconds away, so none lands mid-fade.
        .task(id: still || reduceMotion ? nil : key) { await live() }
        .accessibilityHidden(true)
    }

    private struct FaceRect: Sendable {
        let x, y, w, h: CGFloat
        let colour: UInt8
    }

    /// The faces' colours, by a rectangle's colour byte, made once.
    private static let palette: [Color] = FaceDesigns.colors.map { rgb in
        Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    /// `rects` fitted into `canvas`, one path for each run of a colour, in
    /// order. A design pixel is a fraction of a point here, so each
    /// rectangle filled on its own would smooth its edges, and two that
    /// meet would leave a dark seam between them; filled as one path they
    /// meet seamlessly, and every edge sits on the display's pixel grid
    /// (`scale` pixels a point), so the outline is crisp.
    private static func paths(_ rects: [FaceRect], in canvas: CGSize, scale: CGFloat) -> [(Color, Path)] {
        guard !palette.isEmpty else { return [] }
        let box = FaceDesigns.box
        let s = 0.8 * canvas.width / box.width
        let x0 = (canvas.width - box.width * s) / 2, y0 = (canvas.height - box.height * s) / 2
        let scale = max(scale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        var runs: [(UInt8, Path)] = []
        for r in rects {
            let colour = Int(r.colour) < palette.count ? r.colour : 0
            let left = snap(x0 + r.x * s), top = snap(y0 + r.y * s)
            let rect = CGRect(x: left, y: top, width: snap(x0 + (r.x + r.w) * s) - left, height: snap(y0 + (r.y + r.h) * s) - top)
            if runs.last?.0 == colour { runs[runs.count - 1].1.addRect(rect) } else { runs.append((colour, Path(rect))) }
        }
        return runs.map { (palette[Int($0.0)], $0.1) }
    }

    private static let eyeInk = Color(white: 0.92)

    /// The menu-bar icon's eyes, in a tile `canvas` wide: crosses when
    /// Boop isn't running, bars asleep or blinking, else two tall eyes.
    /// Each path, and whether it's stroked rather than filled.
    private static func eyes(_ mood: FaceMood, shut: Bool, in canvas: CGSize) -> [(Path, Bool)] {
        let u = canvas.width / 20, top = canvas.height / 2 - 3 * u
        return MenuBarIcon.eyes.map { x in
            let x = x * u
            if mood == .stopped {
                var cross = Path()
                cross.move(to: CGPoint(x: x, y: top + u))
                cross.addLine(to: CGPoint(x: x + 4 * u, y: top + 5 * u))
                cross.move(to: CGPoint(x: x + 4 * u, y: top + u))
                cross.addLine(to: CGPoint(x: x, y: top + 5 * u))
                return (cross, true)
            }
            let eye = mood == .asleep || shut ? CGRect(x: x - u, y: top + 4 * u, width: 6 * u, height: 2 * u)
                                              : CGRect(x: x, y: top, width: 4 * u, height: 6 * u)
            return (Path(roundedRect: eye, cornerRadius: min(eye.width, eye.height) / 2), false)
        }
    }

    /// The generated artwork never changes during a launch. Decode it
    /// once instead of allocating bytes and rectangles on every status
    /// update and every blink's two redraws.
    private static let faces = FaceDesigns.faces.mapValues {
        (open: rects($0.open), shut: rects($0.shut))
    }

    private static func rects(_ base64: String) -> [FaceRect] {
        let b = [UInt8](Data(base64Encoded: base64) ?? Data())
        // Five bytes a rectangle. A plain loop: older compilers time out
        // type-checking this as one map expression.
        var out: [FaceRect] = []
        out.reserveCapacity(b.count / 5)
        var i = 0
        while i + 4 < b.count {
            let x = CGFloat(b[i]), y = CGFloat(b[i + 1]), w = CGFloat(b[i + 2]), h = CGFloat(b[i + 3])
            out.append(FaceRect(x: x, y: y, w: w, h: h, colour: b[i + 4]))
            i += 5
        }
        return out
    }

    /// Blinks every few seconds.
    private func live() async {
        guard !reduceMotion, !still, mood != .asleep, mood != .stopped else {
            blink = false
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2400...5200)))
            if Task.isCancelled { return }
            blink = true
            try? await Task.sleep(for: .milliseconds(180))
            blink = false
        }
    }
}

/// The menu-bar icon: two rounded eyes, nothing else, so it reads at 18 pt.
/// Closed while asleep, open while agents idle, with a small dot while they
/// work, amber when something needs you, and crosses when Boop isn't
/// running.
enum MenuBarIcon {
    /// Where the eyes go across the 20 pt canvas: the left one's left
    /// edge, and the right one's, 8 pt on. The dot goes beside the right
    /// eye, so the eyes alone (4 pt, 4 pt apart, 4 pt) and the eyes with
    /// the dot are each within a point of the middle, and the eyes don't
    /// move when the dot comes.
    static let eyes: [CGFloat] = [3, 11]

    /// The coloured one redraws every time it's shown, so it follows the
    /// menu bar between light and dark.
    static func image(_ mood: FaceMood) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            let dark = match == .darkAqua || match == .vibrantDark
            let colour: NSColor = switch mood {
            // The device's amber is too pale on a light bar; a deeper one
            // keeps 3:1 there and still reads as amber.
            case .needsYou: NSColor(hex: dark ? Palette.amber : Palette.menuAmberLight)
            default: .black
            }
            colour.setFill()
            // At 1× the dot and the crosses go pixel by pixel: smoothed, a
            // 3 pt circle reads as a "+" and a diagonal stroke as a smudge.
            let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) } ?? 2
            let pixels = scale < 1.5
            if mood == .stopped {
                // Two crosses where the eyes go.
                colour.setStroke()
                for x in eyes {
                    if pixels {
                        for i in 0..<5 {
                            let d = CGFloat(i)
                            NSRect(x: x + d, y: 7 + d, width: 1, height: 1).fill(using: .sourceOver)
                            NSRect(x: x + 4 - d, y: 7 + d, width: 1, height: 1).fill(using: .sourceOver)
                        }
                        continue
                    }
                    let cross = NSBezierPath()
                    cross.move(to: NSPoint(x: x, y: 7))
                    cross.line(to: NSPoint(x: x + 4, y: 11))
                    cross.move(to: NSPoint(x: x + 4, y: 7))
                    cross.line(to: NSPoint(x: x, y: 11))
                    cross.lineWidth = 1.5
                    cross.lineCapStyle = .round
                    cross.stroke()
                }
                return true
            }
            // Two tall eyes, or two short bars while asleep.
            // Whole points, so they stay crisp at 1×.
            for x in eyes {
                let eye = mood == .asleep ? NSRect(x: x - 1, y: 10, width: 6, height: 2)
                                          : NSRect(x: x, y: 6, width: 4, height: 6)
                NSBezierPath(roundedRect: eye, xRadius: eye.height == 2 ? 1 : 2, yRadius: eye.height == 2 ? 1 : 2).fill()
            }
            // The dot sits up and to the right, clear of the eyes.
            if mood == .working || mood == .needsYou {
                let dot = NSRect(x: eyes[1] + 5, y: 1, width: 3, height: 3)
                if pixels { dot.fill(using: .sourceOver) } else { NSBezierPath(ovalIn: dot).fill() }
            }
            return true
        }
        image.isTemplate = mood != .needsYou
        if !image.isTemplate { image.cacheMode = .never }
        image.accessibilityDescription = "Boop"
        return image
    }
}
