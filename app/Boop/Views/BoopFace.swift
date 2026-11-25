import AppKit
import BoopKit
import SwiftUI

/// Which look the little face shows. The Mac never plays Boop's reactions;
/// this is just enough of the device's face that the popover and the menu
/// bar read as the same creature.
enum FaceMood: Hashable {
    case asleep, idle, working, needsYou, happy
    /// Boop is starting, before its first status: eyes open, faint, so it
    /// never passes for napping.
    case waking
    /// Boop couldn't start: the menu bar's crossed eyes, so it never passes
    /// for napping.
    case stopped

    init(_ status: Runtime.Status?) {
        guard let status else {
            self = .waking
            return
        }
        let s = status.snapshot
        if s.attn != nil {
            self = .needsYou
        } else {
            switch s.doing {
            case "working": self = .working
            case "idle": self = .idle
            default: self = .asleep
            }
        }
    }
}

/// Boop's face on a small black-glass tile, for a pack with no mirror of
/// the board: the menu bar's eyes, at rest, for Boop's look. They blink now
/// and then, and cross-fade into new ones when the look changes.
struct BoopFace: View {
    var mood: FaceMood
    var size: CGFloat

    @ViewState private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotion) private var still

    /// The board's dissolve between pictures: rig::kFadeMs, on its
    /// smoothstep ease, which this curve is exactly.
    private static let fade = Animation.timingCurve(1.0 / 3, 0, 2.0 / 3, 1, duration: 0.2)

    var body: some View {
        ZStack {
            TileShape(side: size).fill(Theme.glass)
            TileEdge(side: size, needsYou: mood == .needsYou)
            ZStack {
                Canvas { context, canvas in
                    for (path, stroke) in Self.eyes(mood, shut: blink, in: canvas) {
                        if stroke {
                            context.stroke(path, with: .color(Self.eyeInk),
                                           style: StrokeStyle(lineWidth: canvas.width * 0.05, lineCap: .round))
                        } else {
                            context.fill(path, with: .color(mood == .asleep ? Self.eyeInk.opacity(0.7) : Self.eyeInk))
                        }
                    }
                }
                .id(mood)
                .transition(.opacity)
                .blendMode(.plusLighter)
            }
            .compositingGroup()
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : Self.fade, value: mood)
        // Either motion setting changes the id, so an existing blink
        // loop stops as soon as motion is turned off. A new look restarts
        // it, its first blink seconds away, so none lands mid-fade.
        .task(id: still || reduceMotion ? nil : mood) { await live() }
        .accessibilityHidden(true)
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
            // Shut, a bar at the eyes' middle.
            let eye = mood == .asleep || shut ? CGRect(x: x - u, y: top + 2 * u, width: 6 * u, height: 2 * u)
                                              : CGRect(x: x, y: top, width: 4 * u, height: 6 * u)
            return (Path(roundedRect: eye, cornerRadius: min(eye.width, eye.height) / 2), false)
        }
    }

    /// Blinks every few seconds.
    private func live() async {
        guard !reduceMotion, !still, mood != .asleep, mood != .stopped, mood != .waking else {
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
/// Closed while asleep, open while agents idle, looking down at the work
/// with a dot beside them while they work, amber with the dot when
/// something needs you, faint while Boop wakes up, and crosses when it
/// isn't running.
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
            // Two tall eyes; two short bars at their middle while asleep;
            // shorter, lower eyes while it works, looking down at the work.
            // Whole points, so they stay crisp at 1×.
            let ink = mood == .waking ? colour.withAlphaComponent(0.45) : colour
            ink.setFill()
            for x in eyes {
                let eye = switch mood {
                case .asleep: NSRect(x: x - 1, y: 8, width: 6, height: 2)
                case .working: NSRect(x: x, y: 8, width: 4, height: 5)
                default: NSRect(x: x, y: 6, width: 4, height: 6)
                }
                let r = min(eye.width, eye.height) / 2
                NSBezierPath(roundedRect: eye, xRadius: r, yRadius: r).fill()
            }
            // The dot sits up and to the right, clear of the eyes: 4 pt, so
            // it reads at 1× as more than a speck.
            if mood == .working || mood == .needsYou {
                let dot = NSRect(x: eyes[1] + 5, y: 0, width: 4, height: 4)
                if pixels {
                    // A pixel circle: the square without its corners.
                    NSRect(x: dot.minX + 1, y: dot.minY, width: 2, height: 4).fill(using: .sourceOver)
                    NSRect(x: dot.minX, y: dot.minY + 1, width: 4, height: 2).fill(using: .sourceOver)
                } else {
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
            return true
        }
        image.isTemplate = mood != .needsYou
        if !image.isTemplate { image.cacheMode = .never }
        image.accessibilityDescription = "Boop"
        return image
    }
}
