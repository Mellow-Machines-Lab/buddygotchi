import AppKit
import BoopKit
import SwiftUI

/// The onboarding window's content: footprints along the top for the
/// acts, the act, and confetti over everything when something goes well.
/// One size, so every act is laid out for it.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    static let size = CGSize(width: 720, height: 560)
    /// Above the footprints, and below every act's buttons.
    static let edge: CGFloat = 30

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                Footprints(act: model.act)
                    .padding(.top, Self.edge)
                    .padding(.bottom, 16)
                // Unclipped, so the on-screen Boop's shadow isn't cut off;
                // the window's edges clip the slide.
                ZStack {
                    act
                        .padding(.horizontal, Theme.windowGutter)
                        .padding(.bottom, Self.edge)
                        .id(model.act)
                        .transition(.asymmetric(
                            insertion: .offset(x: model.forward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: model.forward ? -60 : 60).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .finale: FinaleAct(model: model)
        }
    }
}

// MARK: - Pieces every act uses

/// Little footprints for the acts: walked ones in ink, this one bigger, the
/// rest faint.
struct Footprints: View {
    let act: Onboarding.Act

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Onboarding.Act.allCases, id: \.self) { step in
                let here = step == act, walked = step.index <= act.index
                HStack(alignment: .top, spacing: 3) {
                    Capsule().frame(width: 5, height: 8)
                    Capsule().frame(width: 5, height: 8).offset(y: 4)
                }
                .foregroundStyle(walked ? Theme.ink : Theme.hairlineStrong)
                .scaleEffect(here ? 1.35 : 1)
                .rotationEffect(.degrees(step.index.isMultiple(of: 2) ? -12 : 12))
            }
        }
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
         ("napping", .onboarding(base: "asleep", mood: "comfy")),
         ("looking", .onboarding(mood: "curious")),
         ("jumping", .onboarding(mood: "excited")),
         ("cheeky", .onboarding(mood: "proud"))]
            + WhatIDoAct.Step.allCases.map { ("demo-\($0)", $0.look) }
    }

    /// The on-screen Boop's look, for the mirror: no sound, one agent at most.
    static func onboarding(base: String = "idle", act: String? = nil, mood: String = "happy",
                           waiting: String? = nil) -> StateSnapshot {
        StateSnapshot(base: base, act: act, mood: mood,
                      attn: waiting.map { .init(agent: $0, project: "landing", more: 0, id: 1) },
                      busy: base == "working" ? 1 : 0, vol: 0)
    }
}

/// The on-screen Boop: the character pack's slime, on its black glass, when
/// it has one (Boop's), else its face. A click pokes it.
struct OnboardingBuddy: View {
    @ObservedObject var model: OnboardingModel
    var snapshot: StateSnapshot
    var size: CGFloat
    /// For a 4:3 tile, its height (the slime only).
    var height: CGFloat?
    /// The face, for a pack without the slime.
    var face: FaceMood = .happy

    var body: some View {
        Group {
            if SlimeFeed.folder != nil {
                SlimeFace(feed: model.feed, snapshot: snapshot, live: true, listening: false, size: size, height: height)
            } else {
                BoopFace(mood: face, size: size)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { model.pokeOnScreen() }
        .help("Poke me")
    }
}

/// What Boop says: a rounded bubble in ink, its tail at the bottom left.
struct Bubble: View {
    let text: String
    /// When given, it wraps at this width, growing from its leading edge;
    /// else it's one line.
    var width: CGFloat?

    /// The room a bubble beside a tile takes, at most.
    static let room: CGFloat = 240

    init(_ text: String, width: CGFloat? = nil) {
        self.text = text
        self.width = width
    }

    var body: some View {
        Text(text)
            .font(.boop(17, .bold))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.ink, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4,
                                                             bottomTrailingRadius: 16, topTrailingRadius: 16))
            .fixedSize(horizontal: width == nil, vertical: true)
            .frame(width: width, alignment: .leading)
    }
}

/// An act's title and the line under it.
struct ActTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.boop(26, .bold)).multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
        }
    }
}

/// Back on the left, the act's one filled button on the right, and a
/// quiet second choice beside it.
struct ActNav: View {
    @ObservedObject var model: OnboardingModel
    var next = "Next"
    var enabled = true
    var quiet: (label: String, action: () -> Void)?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            ActBack(model: model)
            Spacer()
            if let quiet {
                Button(quiet.label, action: quiet.action).buttonStyle(.quiet).font(.system(size: 13))
            }
            Button(next) { (action ?? model.next)() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
        }
    }
}

/// Back, when there's somewhere to go back to. Right after the name there
/// isn't, and it says why.
struct ActBack: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        if model.act.back != nil {
            Button("Back") { model.back() }.buttonStyle(.quiet).font(.system(size: 13))
                .keyboardShortcut("[", modifiers: .command)
        } else if model.act.afterNaming {
            Label("I'm \(model.name) now, for keeps", systemImage: "lock")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
        }
    }
}

/// A card on the paper: the popover's, a little roomier. Nothing in
/// onboarding but a choice looks chosen, so a card's emphasis is its tone.
struct OnboardingCard<Content: View>: View {
    var tone: Color?
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 14, tone: tone) { content }
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
            started = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { started = nil }
        }
    }
}

/// Rings spreading out from the middle while Boop looks for its body.
struct Ripples: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.stillMotion) private var still

    var body: some View {
        TimelineView(.animation(paused: reduced || still)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for ring in 0..<3 {
                    let phase = (still || reduced) ? Double(ring) / 3 : (t / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    let w = size.width * (0.45 + 0.55 * phase), h = size.height * (0.45 + 0.55 * phase)
                    let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
                    context.stroke(Path(ellipseIn: rect), with: .color(Theme.hairlineStrong.opacity(1 - phase)), lineWidth: 2)
                }
            }
        }
    }
}
