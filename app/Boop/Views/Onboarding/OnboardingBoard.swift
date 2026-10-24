import AppKit
import BoopKit
import SwiftUI

// Acts 4 and 5: the board, and how to use it.

/// Act 4: plug me in, look for me, tap my screen, and Boop jumps into its
/// body. Without a board it carries on; the board pairs later.
struct BodyAct: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var app: AppModel
    @ViewState private var flown = false
    @Environment(\.stillMotion) private var still

    init(model: OnboardingModel) {
        self.model = model
        app = model.app
    }

    /// After this long looking, a hint for a board that doesn't show up.
    static let hintAfter: TimeInterval = 20

    var body: some View {
        VStack(spacing: 16) {
            switch model.body {
            case .intro: intro
            case .looking: looking
            case .joined: joined
            case .skipped: EmptyView()
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 6)
        .padding(.bottom, 30)
    }

    // MARK: Plug me in

    private var intro: some View {
        VStack(spacing: 18) {
            PlugIn(model: model).frame(height: 170)
            ActTitle(title: "Let's find my body",
                     detail: "Plug the board on your desk into power with its USB cable. Its screen lights up when it's on.")
            if model.hasLink {
                Label("macOS will ask if I can use Bluetooth. Say OK, so I can find my body.", systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            } else {
                Text("This copy of Boop runs without a board.").font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if model.hasLink {
                ActNav(model: model, next: "Look for me", quiet: (label: "I don't have my Boop yet", action: { model.skipBoard() })) {
                    model.lookForBoard()
                }
            } else {
                ActNav(model: model, next: "Next") { model.skipBoard() }
            }
        }
    }

    // MARK: Looking, and found

    private var looking: some View {
        VStack(spacing: 16) {
            ZStack {
                Ripples().frame(width: 360, height: 220)
                OnboardingBuddy(model: model, snapshot: .onboarding(mood: "curious"), size: 140)
            }
            .frame(height: 220)
            if let problem = app.startError {
                ActTitle(title: "I couldn't start", detail: problem)
            } else {
                lookingWords
            }
            Spacer(minLength: 0)
            HStack {
                Button("I don't have my Boop yet", action: model.skipBoard).buttonStyle(.quiet).font(.system(size: 13))
                Spacer()
            }
        }
        .animation(.boopPop, value: model.board)
    }

    @ViewBuilder private var lookingWords: some View {
            switch model.board {
            case .found(let name):
                VStack(spacing: 6) {
                    Text("FOUND \(name.uppercased())")
                        .font(.system(size: 12, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.sageInk)
                    ActTitle(title: "Tap my screen on your desk",
                             detail: "So I know it's me. That's also how you poke me, any time.")
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .trouble(let why):
                ActTitle(title: "I can't look for my body", detail: why)
                Button("Open Bluetooth settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                }
                .buttonStyle(.row)
            case .none:
                // Looked at again now and then, for the hint.
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    ActTitle(title: "Looking for my body…", detail: hint)
                }
            }
    }

    private var hint: String {
        guard let since = model.lookingSince, Date().timeIntervalSince(since) > Self.hintAfter else {
            return "Keep me plugged in and close by."
        }
        return "Can't see me yet. Is my screen on? Try unplugging me and plugging me back in."
    }

    // MARK: Joined

    private var joined: some View {
        VStack(spacing: 14) {
            ZStack {
                // The on-screen Boop leaps off toward the desk…
                OnboardingBuddy(model: model, snapshot: .onboarding(mood: "excited"), size: 150)
                    .rotationEffect(.degrees(still || flown ? 28 : 0))
                    .scaleEffect(still || flown ? 0.3 : 1)
                    .offset(x: still || flown ? 300 : 0, y: still || flown ? 120 : 0)
                    .opacity(still || flown ? 0 : 1)
                // …and the board on the desk wakes up.
                DeskBoard(model: model)
                    .scaleEffect(still || flown ? 1 : 0.6)
                    .opacity(still || flown ? 1 : 0)
            }
            .frame(height: 210)
            ActTitle(title: "There you are!", detail: "That's me on your desk. Say hi to my body.")
            if let firmware = app.firmwareOffer {
                snack(firmware)
            } else if let device = app.status?.device, !device.hasTheVoice {
                OnboardingCard {
                    Label("I've lost my voice: there's no voice file on my card. I'll still show everything; Settings says how to fix it.",
                          systemImage: "speaker.slash")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
            ActNav(model: model)
        }
        .task {
            guard !still else { return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flown = true }
        }
    }

    /// Older firmware than the app carries: a snack, over USB.
    private func snack(_ firmware: BoardFirmware) -> some View {
        OnboardingCard(highlight: Theme.amber) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("I'm a bit hungry. Feed me an update?").font(.boop(14, .bold))
                    Text(snackDetail(firmware)).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                switch app.firmwareWrite {
                case .idle, .failed: Button("Update") { app.updateFirmware() }.buttonStyle(.rowFilled)
                case .writing, .done: EmptyView()
                }
            }
        }
    }

    private func snackDetail(_ firmware: BoardFirmware) -> String {
        switch app.firmwareWrite {
        case .idle: "Firmware \(firmware.version). Plug me into this Mac with a USB cable, then update. About half a minute."
        case .writing(let done): "Eating… \(Int(done * 100))%. Keep the cable in."
        case .done(let version): "Yum. I'm on \(version) now."
        case .failed(let why): "Couldn't: \(why)"
        }
    }
}

/// The board on the desk, as act 4 draws it: Boop napping on its screen,
/// its cable running to a plug, waiting to be found.
private struct PlugIn: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 0) {
            OnboardingBuddy(model: model, snapshot: .onboarding(base: "asleep", mood: "comfy"), size: 150, face: .asleep)
                .overlay(alignment: .topTrailing) {
                    Text("z z")
                        .font(.boop(18, .heavy))
                        .foregroundStyle(Theme.inkSoft)
                        .offset(x: 18, y: -14)
                }
            Capsule().fill(Theme.hairlineStrong).frame(width: 90, height: 8)
            RoundedRectangle(cornerRadius: 6).fill(Theme.inkSoft).frame(width: 30, height: 22)
                .overlay { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Theme.amber) }
        }
        .accessibilityElement()
        .accessibilityLabel("The board, plugged into power, napping")
    }
}

/// The board after the jump: its screen, awake, on a little desk.
private struct DeskBoard: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBuddy(model: model, snapshot: .onboarding(mood: "happy"), size: 160)
            RoundedRectangle(cornerRadius: 3).fill(Theme.hairlineStrong).frame(width: 260, height: 6)
        }
    }
}

/// Act 5: how to use me. With the board, each lesson waits for it to be
/// done on the board; without one, they're shown.
struct HowToAct: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.stillMotion) private var still

    private var paired: Bool { model.body == .joined }

    var body: some View {
        VStack(spacing: 14) {
            ActTitle(title: "Here's how we get along",
                     detail: paired ? nil : "You'll try these on my body when we meet.")
            VStack(spacing: 8) {
                lesson(1, "Tap my screen", "I poke back. Tap a lot and I get grumpy.", done: model.lessons.contains(.tap))
                lesson(2, "Press my button", paired ? "The one on my side. A short press pokes me too. Try it now."
                                                    : "The one on my side. A short press pokes me too.",
                       done: model.lessons.contains(.button), waiting: paired && model.lessons.contains(.tap))
                lesson(3, "Hold my button and talk", "I listen while you hold it, then answer. Or use Talk on the Mac.")
                lesson(4, "When I glow amber, tap me", "An agent is waiting for you. A tap opens it on your Mac.", amber: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT MY FACES MEAN").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 8) {
                    face("Napping", "no agents open")
                    face("Focused", "agents at work")
                    face("Amber", "someone needs you", amber: true)
                    face("Trophy", "a big finish")
                }
            }
            Spacer(minLength: 0)
            ActNav(model: model, next: "Got it")
        }
        .padding(.horizontal, 48)
        .padding(.top, 2)
        .padding(.bottom, 30)
        .task {
            // Without a board, the on-screen Boop shows the poke now and then.
            guard !paired, !still else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                model.feed.reaction(id: 0, DeviceReaction(anim: "poked"))
            }
        }
    }

    private func lesson(_ number: Int, _ title: String, _ detail: String, done: Bool = false, waiting: Bool = false,
                        amber: Bool = false) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.sage : waiting ? Theme.ink : amber ? Theme.amber : Theme.hairline)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.paper)
                } else {
                    Text("\(number)").font(.boop(13, .bold)).foregroundStyle(waiting ? Theme.paper : Theme.ink)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.boop(15, .bold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if waiting && !done {
                Text("waiting…").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(waiting && !done ? Theme.paper : Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(waiting && !done ? Theme.ink : .clear, lineWidth: 2) }
        .animation(.boopPop, value: done)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "")
    }

    private func face(_ title: String, _ detail: String, amber: Bool = false) -> some View {
        OnboardingCard(highlight: amber ? Theme.amber : nil) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.boop(13, .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}
