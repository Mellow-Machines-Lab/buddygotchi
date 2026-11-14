import AppKit
import BoopKit
import SwiftUI

/// The onboarding window's content: footprints along the top for the
/// acts, the act, and confetti over everything when something goes well.
/// One size, so every act is laid out for it, in one frame (`ActFrame`):
/// the footprints and the bar never move from one act or state to the next.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    static let size = CGSize(width: 720, height: 560)
    /// Above the footprints, and below every act's bar.
    static let edge: CGFloat = 30

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                Footprints(act: model.act)
                    .padding(.top, Self.edge)
                // Unclipped, so the on-screen Boop's shadow isn't cut off;
                // the window's edges clip the slide. The act has the rest
                // of the window, whatever it holds: its body scrolls
                // before it grows.
                ZStack {
                    act
                        .padding(.horizontal, Theme.windowGutter)
                        .id(model.act)
                        .transition(.asymmetric(
                            insertion: .offset(x: model.forward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: model.forward ? -60 : 60).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Theme.gutter)
                .padding(.bottom, Self.edge)
            }
            Confetti(bursts: model.confetti)
                .allowsHitTesting(false)
            // ⌘Q quits, as a menu would: an accessory app has none.
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
    }

    @ViewBuilder private var act: some View {
        switch model.act {
        case .hello: HelloAct(model: model)
        case .whatIDo: WhatIDoAct(model: model)
        case .makeMeYours: MakeMeYoursAct(model: model)
        case .body: BodyAct(model: model)
        case .howTo: HowToAct(model: model)
        case .agents: AgentsAct(model: model)
        case .smallThings: SmallThingsAct(model: model)
        case .world: WorldAct(model: model)
        case .finale: FinaleAct(model: model)
        }
    }
}

// MARK: - The frame

/// Onboarding's sizes, one of each, so nothing in the frame moves.
enum ActSize {
    /// The footprints' box.
    static let marks: CGFloat = 20
    /// The face over a hero act's title.
    static let hero: CGFloat = 150
    /// Act 1's entrance, the one larger face.
    static let entrance: CGFloat = 196
    /// Act 1's slot: the entrance face at its foot, room for the bubble
    /// above.
    static let entranceSlot: CGFloat = 260
    /// The face beside a list act's title, and the moods' legend.
    static let side: CGFloat = 64
    /// The bar, and its main button.
    static let bar: CGFloat = 32
    /// The narrowest the main button's label is, so "Next" isn't a stub:
    /// with its sides, a 72 pt button.
    static let primary: CGFloat = 40
    /// Every control in a card's column: a switch's box, a button, a field.
    static let control: CGFloat = 28
    /// That column's width, so the controls line up down the act.
    static let controls: CGFloat = 72
    /// A hero act's body and its lead, narrower than the window for lines
    /// that read.
    static let heroBody: CGFloat = 520
    static let lead: CGFloat = 440
    /// The hooks' panel in act 6, as tall as the act has room for.
    static let panel: CGFloat = 220
    /// The fade at a scrolling body's foot.
    static let fade: CGFloat = 16
}

extension Font {
    /// Onboarding's notes, links and buttons: between the lead and the body.
    static let note = Font.system(size: 13)
}

/// Every act's frame, in one of two shapes. A hero act (1, 3, 4, 8, 9) has
/// its face in a slot of fixed height, then the title at one height, then
/// its body; a list act (2, 5, 6, 7) has its face beside the title at the
/// top, then a left-aligned body. The body is centred in the room it has
/// and never grows past it: it scrolls inside, with a fade. The bar is
/// always at the foot.
struct ActFrame<Face: View, Content: View>: View {
    enum Kind { case hero, list }
    var kind: Kind
    var title: String?
    var lead: String?
    /// The hero slot's height: the hero face's, or act 1's entrance.
    var slot: CGFloat = ActSize.hero
    /// A list act without its face beside the title: its body holds one.
    var faced = true
    var bar: ActBar
    @ViewBuilder var face: Face
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            switch kind {
            case .hero:
                face.frame(maxWidth: .infinity).frame(height: slot)
                if let title {
                    ActTitle(title: title, detail: lead).padding(.top, Theme.gapSection)
                }
                ActBody(width: ActSize.heroBody) { content }
            case .list:
                HStack(spacing: Theme.gutter) {
                    if faced, Face.self != EmptyView.self { face.frame(width: ActSize.side, height: ActSize.side) }
                    if let title { ActTitle(title: title, detail: lead, leading: true) }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: ActSize.side)
                ActBody { content }
            }
            bar
        }
    }
}

/// An act's body: centred in its room, and scrolled with a fade at its
/// foot, with no scroller, when it's taller.
struct ActBody<Content: View>: View {
    var width: CGFloat?
    @ViewBuilder var content: Content
    @ViewState private var tall: CGFloat = 0

    var body: some View {
        GeometryReader { room in
            let over = tall > room.size.height + 1
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: width ?? .infinity)
                    .frame(maxWidth: .infinity)
                    .background(GeometryReader { box in Color.clear.preference(key: BodyHeight.self, value: box.size.height) })
                    .frame(minHeight: room.size.height)
            }
            .scrollIndicators(.never)
            .scrollDisabled(!over)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(over ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: ActSize.fade)
                }
            }
        }
        .onPreferenceChange(BodyHeight.self) { tall = $0 }
        .padding(.vertical, Theme.gutter)
    }
}

private struct BodyHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Little footprints for the acts: walked ones in ink, the rest faint, this
/// one bigger with a dot under it. In a box of their own height, and
/// each pair the other's mirror image, so they stand at one height
/// whichever act it is.
struct Footprints: View {
    let act: Onboarding.Act
    static let foot = CGSize(width: 6, height: 10), stride: CGFloat = 4, here: CGFloat = 1.5

    var body: some View {
        HStack(spacing: Theme.gap) {
            ForEach(Onboarding.Act.allCases, id: \.self) { step in
                let here = step == act, walked = step.index <= act.index
                HStack(alignment: .top, spacing: Theme.gapTight) {
                    Capsule().frame(width: Self.foot.width, height: Self.foot.height)
                    Capsule().frame(width: Self.foot.width, height: Self.foot.height).offset(y: Self.stride)
                }
                .foregroundStyle(walked ? Theme.ink : Theme.inkFaint)
                .rotationEffect(.degrees(12))
                .scaleEffect(x: step.index.isMultiple(of: 2) ? 1 : -1)
                .scaleEffect(here ? Self.here : 1)
                .overlay(alignment: .bottom) {
                    // Under the bigger pair, clear of its feet.
                    Circle().fill(Theme.ink).frame(width: 3, height: 3)
                        .offset(y: Theme.gap)
                        .opacity(here ? 1 : 0)
                }
            }
        }
        .frame(height: ActSize.marks)
        .animation(.boopPop, value: act)
        .accessibilityElement()
        .accessibilityLabel("Step \(act.index + 1) of \(Onboarding.Act.allCases.count)")
    }
}

extension StateSnapshot {
    /// Every look onboarding gives the on-screen Boop, by name, for the
    /// snapshots to draw each through the slime engine.
    static var onboardingLooks: [(String, StateSnapshot)] {
        [("hello", .onboarding(mood: "happy")),
         ("napping", .onboarding(doing: "asleep", mood: "comfy")),
         ("looking", .onboarding(mood: "curious")),
         ("stuck", .onboarding(mood: "sad")),
         ("jumping", .onboarding(mood: "excited"))]
            + WhatIDoAct.Step.allCases.map { ("demo-\($0)", $0.look(drops: 3)) }
    }

    /// The on-screen Boop's look, for the mirror: no sound, one agent at most.
    static func onboarding(doing: String = "idle", activity: String? = nil, mood: String = "happy",
                           waiting: String? = nil) -> StateSnapshot {
        StateSnapshot(doing: doing, activity: activity, mood: mood,
                      attn: waiting.map { .init(agent: $0, project: "landing", more: 0, id: 1) },
                      working: doing == "working" ? 1 : 0, vol: 0)
    }
}

extension OnboardingModel {
    /// The on-screen Boop's look in this act and state: napping before it's
    /// found, curious while it looks, sad when it's stuck, excited at the
    /// world and the finale. The acts draw it, and the snapshots give each
    /// picture its still from it.
    var look: StateSnapshot {
        switch act {
        case .whatIDo: return WhatIDoAct.Step.asking.look(drops: 0)
        case .body:
            switch body {
            case .intro, .skipped: return .onboarding(doing: "asleep", mood: "comfy")
            case .looking: return stuck ? .onboarding(mood: "sad") : .onboarding(mood: "curious")
            case .joined: return .onboarding(mood: "happy")
            }
        case .agents: return heard == nil ? .onboarding(mood: "curious") : live
        case .world, .finale: return .onboarding(mood: "excited")
        case .hello, .makeMeYours, .howTo, .smallThings: return .onboarding(mood: "happy")
        }
    }

    /// Boop couldn't start, or can't use Bluetooth: nothing's looking.
    var stuck: Bool {
        if app.startError != nil { return true }
        if case .trouble = board { return true }
        return false
    }
}

/// The on-screen Boop: the character pack's slime, on its black glass, when
/// it has one (Boop's), else its face. A click pokes it. On dark paper the
/// glass has a hairline edge, which its shadow can't give it there.
struct OnboardingBuddy: View {
    @ObservedObject var model: OnboardingModel
    var snapshot: StateSnapshot
    var size: CGFloat
    /// For a 4:3 tile, its height (the slime only).
    var height: CGFloat?
    /// The face, for a pack without the slime.
    var face: FaceMood = .happy
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if SlimeFeed.folder != nil {
                SlimeFace(feed: model.feed, snapshot: snapshot, live: true, size: size, height: height)
                    .overlay {
                        if scheme == .dark {
                            RoundedRectangle(cornerRadius: min(size, height ?? size) * 0.27)
                                .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
                        }
                    }
            } else {
                BoopFace(mood: face, size: size)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { model.pokeOnScreen() }
        .help("Poke me")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Poke me")
        .accessibilityAction { model.pokeOnScreen() }
    }
}

/// A numbered step to do, done on the board: ticked once done, edged in
/// ink with "waiting…" on its title's line while it's the one to do now;
/// amber's, which is what it means, has its dot, and is toned amber
/// while it's waiting. Its detail keeps room for two lines, so a row
/// doesn't grow as its words change.
struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    var done = false
    var waiting = false
    var amber = false
    /// Tighter, for an act with more on it: its detail takes only the room
    /// it needs.
    var compact = false
    static let mark: CGFloat = 24
    /// Where its title starts: past the row's side, the mark and its gap,
    /// for what goes under a lesson.
    static let indent: CGFloat = 52

    var body: some View {
        let now = waiting && !done
        let tone = amber ? Theme.amber : Theme.ink
        Card(padding: 0, tone: now ? tone : nil) {
            HStack(alignment: .top, spacing: Theme.gap) {
                ZStack {
                    Circle().fill(done ? Theme.sage : now ? Theme.ink : Theme.hairline)
                    if done {
                        Image(systemName: "checkmark").font(.bodyStrong).foregroundStyle(Theme.paper)
                    } else {
                        Text("\(number)").font(.boopLabel).foregroundStyle(now ? Theme.paper : Theme.ink)
                    }
                }
                .frame(width: Self.mark, height: Self.mark)
                VStack(alignment: .leading, spacing: Theme.hair) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        Text(title).font(.boopHeading)
                        if amber { StateDot(tone: Theme.amber) }
                        Spacer(minLength: Theme.gapSnug)
                        if now { Text("waiting…").font(.bodyMedium).foregroundStyle(Theme.inkSoft) }
                    }
                    Text(detail).font(.body).foregroundStyle(Theme.inkSoft)
                        .lineLimit(compact ? 1... : 2...)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.gapSnug)
        }
        .overlay {
            if now {
                RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.ink, lineWidth: 1.5)
            }
        }
        .animation(.boopPop, value: done)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "")
    }
}

/// What Boop says: a rounded bubble in ink, its tail at the bottom corner
/// toward the face. It wraps at the width it's given.
struct Bubble: View {
    let text: String
    /// The face is on its trailing side: act 1's bubble is left of it.
    var tailTrailing = false

    init(_ text: String, tailTrailing: Bool = false) {
        self.text = text
        self.tailTrailing = tailTrailing
    }

    var body: some View {
        Text(text)
            .font(.boopTitle)
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.gapSnug)
            .background(Theme.ink, in: UnevenRoundedRectangle(topLeadingRadius: Theme.gutter,
                                                             bottomLeadingRadius: tailTrailing ? Theme.gutter : Theme.gapTight,
                                                             bottomTrailingRadius: tailTrailing ? Theme.gapTight : Theme.gutter,
                                                             topTrailingRadius: Theme.gutter))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An act's title and the line under it: centred over a hero act, from
/// the face's edge in a list act. A long name takes two lines, then
/// shrinks.
struct ActTitle: View {
    let title: String
    var detail: String?
    var leading = false

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: leading ? Theme.gapTight : Theme.gapSnug) {
            Text(title).font(.boopDisplay)
                .lineLimit(2).minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.lead)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: leading ? nil : ActSize.lead)
            }
        }
        .multilineTextAlignment(leading ? .leading : .center)
    }
}

/// The one bar every act has: Back (or the name's lock) on the left, the
/// main button on the right, always there, and one quiet second choice
/// just left of it. While something is waiting the main button is off,
/// with a spinner; off, it's an outline whose label still reads.
struct ActBar: View {
    @ObservedObject var model: OnboardingModel
    var next = "Next"
    var enabled = true
    var busy = false
    var quiet: (label: String, action: () -> Void)?
    var action: (() -> Void)?
    /// Act 1 shows its bar once Boop has said hi.
    var shown = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ActBack(model: model)
            Spacer(minLength: Theme.gutter)
            if let quiet {
                Button(quiet.label, action: quiet.action).buttonStyle(.quiet).font(.note)
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Button { (action ?? model.next)() } label: {
                HStack(spacing: Theme.gapSnug) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(next)
                }
                .frame(minWidth: ActSize.primary)
            }
            .buttonStyle(ActButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled || busy)
            .help(enabled || busy ? "" : "Finish this step, or take the other way on")
        }
        .frame(height: ActSize.bar)
        .opacity(shown ? 1 : 0)
    }
}

/// The bar's main button: filled, as everywhere; off, an outline on the
/// card's paper with a soft label, readable, not a faded slab.
struct ActButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.wellRadius)
        return configuration.label
            .font(.note.weight(.semibold))
            .foregroundStyle(enabled ? Theme.fillLabel : Theme.inkSoft)
            .padding(.horizontal, Theme.gutter)
            .frame(minHeight: ActSize.bar)
            .background(enabled ? (configuration.isPressed ? Theme.fillPressed : Theme.fill) : Theme.raised, in: shape)
            .overlay(shape.strokeBorder(enabled ? .clear : Theme.hairlineStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.boopSettle, value: configuration.isPressed)
            .contentShape(shape)
    }
}

/// A button in a card's control column: outlined, as tall as the column's
/// other controls.
struct ActControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.wellRadius)
        return configuration.label
            .font(.note.weight(.medium))
            .foregroundStyle(enabled ? Theme.ink : Theme.inkSoft)
            .padding(.horizontal, Theme.gap)
            .frame(minWidth: ActSize.controls, minHeight: ActSize.control)
            .background(hovering || configuration.isPressed ? Theme.well : Theme.lifted, in: shape)
            .overlay(shape.strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

/// Back, when there's somewhere to go back to, its word lined up with the
/// window's edge. Right after the name there isn't, and it says why, on
/// one line.
struct ActBack: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        if model.act.back != nil {
            Button("Back") { model.back() }.buttonStyle(.quiet).font(.note)
                .keyboardShortcut("[", modifiers: .command)
                .fixedSize()
                .padding(.leading, -Theme.gapSnug)
        } else if model.act.afterNaming {
            // The first to give way when the bar is short of room: its
            // name is cut in the middle, on one line.
            Label("I'm \(model.name) now, for keeps", systemImage: "lock")
                .font(.note).foregroundStyle(Theme.inkSoft)
                .lineLimit(1).truncationMode(.middle)
                .layoutPriority(-2)
        }
    }
}

extension View {
    /// On a card that's dark in either appearance: onboarding's terminal,
    /// and the agent's hello.
    func terminalCard() -> some View {
        background(Theme.terminal, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.terminalEdge, lineWidth: 1))
    }
}

// MARK: - Motion

/// Bursts of confetti from the middle of the window, one for each step of
/// `bursts`. Nothing under Reduce Motion, or held still.
struct Confetti: View {
    let bursts: Int
    @ViewState private var started: Date?
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.stillMotion) private var still
    static let pieces = 70, duration = 2.2

    var body: some View {
        TimelineView(.animation(paused: started == nil)) { timeline in
            Canvas { context, size in
                guard let started else { return }
                let t = timeline.date.timeIntervalSince(started)
                guard t < Self.duration else { return }
                let colours = [Theme.amber, Theme.blush, Theme.sage, Color(hex: "#3A9BF0"), Theme.ink]
                for i in 0..<Self.pieces {
                    // Each piece's own direction, speed, spin and colour, from its number.
                    let a = Double((i * 137) % 360) * .pi / 180
                    let speed = 260 + Double((i * 53) % 220)
                    let x = size.width / 2 + cos(a) * speed * t
                    let y = size.height * 0.42 + sin(a) * speed * t * 0.8 + 420 * t * t
                    var piece = context
                    piece.opacity = max(0, 1 - t / Self.duration)
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(Double(i * 29) + t * 360 * (i.isMultiple(of: 2) ? 1 : -1)))
                    let rect = CGRect(x: -4, y: -7, width: 8, height: i.isMultiple(of: 3) ? 8 : 14)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colours[i % colours.count]))
                }
            }
        }
        .onChange(of: bursts) {
            guard !reduced, !still else { return }
            // A burst while one plays starts again; the first's end
            // mustn't cut the second short.
            let burst = Date()
            started = burst
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { if started == burst { started = nil } }
        }
    }
}

/// Rings spreading out from the middle while Boop looks for its body: each
/// grows from the tile's edge, 62% of the frame, to all of it in 2.4 s as
/// it fades, a third of the way behind the one before. Held still, they
/// rest a third apart.
struct Ripples: View {
    static let rings = 3, seconds = 2.4, from = 0.62
    /// Around the hero tile, clear of the footprints and the title.
    static let frame = CGSize(width: 360, height: 180)
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.stillMotion) private var still

    var body: some View {
        if still || reduced {
            Canvas { context, size in
                for ring in 0..<Self.rings {
                    let phase = Double(ring) / Double(Self.rings)
                    context.stroke(Path(ellipseIn: Self.ellipse(phase, in: size)), with: .color(Theme.inkFaint.opacity(1 - phase)),
                                   lineWidth: 2)
                }
            }
        } else {
            // Core Animation runs them in the window server, where a
            // timeline would draw the window again on every frame.
            RippleRings(tone: Theme.inkFaint)
        }
    }

    /// A ring `phase` of the way out, in a frame of `size`.
    static func ellipse(_ phase: Double, in size: CGSize) -> CGRect {
        let grown = from + (1 - from) * phase
        let w = size.width * grown, h = size.height * grown
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

private struct RippleRings: NSViewRepresentable {
    var tone: Color

    func makeNSView(context: Context) -> RippleRingsView { RippleRingsView() }
    func updateNSView(_ view: RippleRingsView, context: Context) { view.tone = NSColor(tone) }
}

final class RippleRingsView: NSView {
    private let rings = (0..<Ripples.rings).map { _ in CAShapeLayer() }
    private var laidOut = CGSize.zero
    var tone = NSColor.clear {
        didSet { paint() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for ring in rings {
            ring.fillColor = nil
            ring.lineWidth = 2
            layer?.addSublayer(ring)
        }
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Each ring's path from 45% to the whole frame, and its fade, again
    /// and again, started a third of a lap apart.
    override func layout() {
        super.layout()
        guard bounds.size != laidOut, bounds.width > 0 else { return }
        laidOut = bounds.size
        let now = CACurrentMediaTime()
        for (i, ring) in rings.enumerated() {
            ring.frame = bounds
            let grow = CABasicAnimation(keyPath: "path")
            grow.fromValue = CGPath(ellipseIn: Ripples.ellipse(0, in: bounds.size), transform: nil)
            grow.toValue = CGPath(ellipseIn: Ripples.ellipse(1, in: bounds.size), transform: nil)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let lap = CAAnimationGroup()
            lap.animations = [grow, fade]
            lap.duration = Ripples.seconds
            lap.repeatCount = .infinity
            lap.timingFunction = CAMediaTimingFunction(name: .linear)
            lap.beginTime = now - Ripples.seconds * Double(i) / Double(rings.count)
            lap.isRemovedOnCompletion = false
            ring.add(lap, forKey: "ripple")
        }
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for ring in rings { ring.strokeColor = tone.cgColor }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
