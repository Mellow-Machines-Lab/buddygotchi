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
                // Rings while looking; none while something stops it.
                if !stuck { Ripples().frame(width: 360, height: 220) }
                OnboardingBuddy(model: model, snapshot: .onboarding(mood: "curious"), size: 140)
            }
            .frame(height: 220)
            if let problem = app.startError {
                ActTitle(title: "I couldn't start", detail: problem)
                Button("Try again", action: model.startRuntime).buttonStyle(.row)
            } else {
                lookingWords
            }
            Spacer(minLength: 0)
            HStack {
                ActBack(model: model)
                Spacer()
                Button("I don't have my Boop yet", action: model.skipBoard).buttonStyle(.quiet).font(.system(size: 13))
            }
        }
        .animation(.boopPop, value: model.board)
    }

    /// Boop couldn't start, or can't use Bluetooth: nothing's looking.
    private var stuck: Bool {
        if app.startError != nil { return true }
        if case .trouble = model.board { return true }
        return false
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
            case .trouble(let device):
                ActTitle(title: "I can't look for my body", detail: device.detail)
                if case .system(let label, let url)? = device.fix {
                    Button(label) { NSWorkspace.shared.open(url) }.buttonStyle(.row)
                }
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
                // The on-screen Boop leaps off toward the desk, and leaves:
                // one slime on the page at a time…
                if !(still || flown) {
                    OnboardingBuddy(model: model, snapshot: .onboarding(mood: "excited"), size: 150)
                        .transition(.asymmetric(insertion: .identity, removal: .scale(scale: 0.3)
                            .combined(with: .offset(x: 300, y: 120)).combined(with: .opacity)))
                }
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
                Card(padding: 14) {
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
        Card(padding: 14) {
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
                .overlay { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Theme.paper) }
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
    @ObservedObject var app: AppModel
    @Environment(\.stillMotion) private var still

    init(model: OnboardingModel) {
        self.model = model
        app = model.app
    }

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
                lesson(3, "Hold my button and talk", talkDetail, done: model.lessons.contains(.talk),
                       waiting: paired && model.lessons.contains(.button))
                lesson(4, "When I glow amber, tap me", "An agent is waiting for you. A tap opens it on your Mac.", amber: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT MY FACES MEAN").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 8) {
                    face(.asleep, "Napping", "no agents open")
                    face(.working, "Focused", "agents at work")
                    face(.needsYou, "Needs you", "an agent waits")
                    face(.idle, design: "proud", "Proud", "a big finish")
                }
            }
            Spacer(minLength: 0)
            ActNav(model: model, next: "Got it")
        }
        .task {
            // Without a board, the on-screen Boop shows the poke now and then.
            guard !paired, !still else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                model.feed.poke()
            }
        }
    }

    /// The talk lesson's words: how, what the Mac heard, or why it can't
    /// hear. Without Jev's key, which act 7 asks for, nothing answers yet.
    private var talkDetail: String {
        guard paired else { return "I listen while you hold it, then answer. Or use Talk on the Mac." }
        if let why = app.status?.micTrouble { return why }
        let later = app.noKey ? " I'll answer once I have a brain, in a couple of steps." : ""
        switch model.talk {
        case .heard(let words): return "I heard “\(Self.quoted(words))”." + later
        case .nothing: return "I didn't catch that. Keep holding while you talk, then let go."
        case nil: return "Hold it, say hi, then let go. macOS asks for the microphone the first time."
        }
    }

    /// What was heard, cut short at a word.
    static func quoted(_ words: String, most: Int = 48) -> String {
        guard words.count > most else { return words }
        let cut = words.prefix(most)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    /// A lesson; the one to do now is toned, and amber's, which is what
    /// it means, has its dot.
    private func lesson(_ number: Int, _ title: String, _ detail: String, done: Bool = false, waiting: Bool = false,
                        amber: Bool = false) -> some View {
        let now = waiting && !done
        return Card(padding: 0, tone: now ? Theme.ink : nil) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Theme.sage : now ? Theme.ink : Theme.hairline)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.paper)
                    } else {
                        Text("\(number)").font(.boop(13, .bold)).foregroundStyle(now ? Theme.paper : Theme.ink)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.boop(15, .bold))
                        if amber { StateDot(tone: Theme.amber) }
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if now {
                    Text("waiting…").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .animation(.boopPop, value: done)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "")
    }

    /// The legend's tiles: the popover's still faces.
    static let faceTile: CGFloat = 44

    /// One face of the legend, on the paper: something to read, not a card to pick.
    private func face(_ mood: FaceMood, design: String = MoodOutput.initial, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.gapSnug) {
            BoopFace(mood: mood, design: design, size: Self.faceTile)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.boop(13, .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
