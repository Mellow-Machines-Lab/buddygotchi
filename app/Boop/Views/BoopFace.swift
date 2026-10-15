import AppKit
import BoopKit
import SwiftUI

/// Which look the little face shows. The Mac never plays Boop's moments;
/// this is just enough of the device's face that the popover and the menu
/// bar read as the same creature.
enum FaceMood: Hashable {
    case asleep, idle, working, needsYou, happy
    /// Setup's preview of a cheeky Boop.
    case cheeky
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
/// then, and blinks into a new face when the mood or the look changes, as
/// the device does.
struct BoopFace: View {
    var mood: FaceMood
    /// Boop's mood, which picks the set of designs.
    var design: String = MoodAction.initial
    var size: CGFloat

    @ViewState private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotion) private var still

    /// The design the tile shows. Asleep and setup's previews are the
    /// pack's startup mood's: the engine names no mood of its own.
    private var key: String {
        let startup = CharacterPack.active.startupMood
        return switch mood {
        case .asleep, .stopped: "\(startup)/asleep"
        case .idle: "\(MoodGraph.pixelFallback(design))/idle"
        case .working: "\(MoodGraph.pixelFallback(design))/working"
        case .needsYou: "\(MoodGraph.pixelFallback(design))/needs_you"
        case .happy, .cheeky: "\(startup)/idle"
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
            Canvas { context, canvas in
                let box = FaceDesigns.box
                let s = 0.8 * canvas.width / box.width
                let x0 = (canvas.width - box.width * s) / 2, y0 = (canvas.height - box.height * s) / 2
                for r in rects {
                    let rgb = FaceDesigns.colors[Int(r.colour) < FaceDesigns.colors.count ? Int(r.colour) : 0]
                    let colour = Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255,
                                       blue: Double(rgb & 0xFF) / 255)
                    context.fill(Path(CGRect(x: x0 + r.x * s, y: y0 + r.y * s, width: r.w * s, height: r.h * s)),
                                 with: .color(mood == .asleep ? colour.opacity(0.7) : colour))
                }
            }
        }
        .frame(width: size, height: size)
        // Either motion setting changes the id, so an existing blink
        // loop stops as soon as motion is turned off.
        .task(id: still || reduceMotion ? nil : key) { await live() }
        .accessibilityHidden(true)
    }

    private struct FaceRect: Sendable {
        let x, y, w, h: CGFloat
        let colour: UInt8
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

    /// Blinks into the new face, then every few seconds.
    private func live() async {
        guard !reduceMotion, !still, mood != .asleep else {
            blink = false
            return
        }
        var first = true
        while !Task.isCancelled {
            if !first {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 2400...5200)))
                if Task.isCancelled { return }
            }
            blink = true
            try? await Task.sleep(for: .milliseconds(first ? 150 : 180))
            blink = false
            first = false
        }
    }
}

/// The menu-bar icon: two rounded eyes, nothing else, so it reads at 18 pt.
/// Closed while asleep, open while agents idle, with a small dot while they
/// work, amber when something needs you, and crosses when Boop isn't
/// running.
enum MenuBarIcon {
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
            if mood == .stopped {
                // Two crosses where the eyes go.
                colour.setStroke()
                for x: CGFloat in [4, 12] {
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
            for x: CGFloat in [4, 12] {
                let eye = mood == .asleep ? NSRect(x: x - 1, y: 10, width: 6, height: 2)
                                          : NSRect(x: x, y: 6, width: 4, height: 6)
                NSBezierPath(roundedRect: eye, xRadius: eye.height == 2 ? 1 : 2, yRadius: eye.height == 2 ? 1 : 2).fill()
            }
            // The dot sits up and to the right, clear of the eyes.
            if mood == .working || mood == .needsYou {
                NSBezierPath(ovalIn: NSRect(x: 17, y: 1, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = mood != .needsYou
        if !image.isTemplate { image.cacheMode = .never }
        image.accessibilityDescription = "Boop"
        return image
    }
}
