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
        // Looked at again now and then, for the hint while it looks.
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            ActFrame(kind: .hero, title: words.title, lead: words.lead, bar: bar) {
                hero
            } content: {
                content
            }
        }
        .animation(.boopPop, value: model.board)
        .task(id: model.body == .joined) {
            guard model.body == .joined, !still else { return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { flown = true }
        }
    }

    /// Where the body is when it's the simulator: its window.
    static let onSimulator = "My body is the simulator window: a board with its screen, button and sounds. It opens beside this one."

    /// The title and the line under it, in each state.
    private var words: (title: String, lead: String?) {
        switch model.body {
        case .intro, .skipped:
            return ("Let's find my body", model.onSimulator ? Self.onSimulator
                    : "Plug the board on your desk into power with its USB cable. Its screen lights up when it's on.")
        case .joined:
            return ("There you are!", "That's me \(model.onSimulator ? app.simulatorWhere : "on your desk"). Say hi to my body.")
        case .looking:
            if let problem = app.startError { return ("I couldn't start", problem) }
            switch model.board {
            case .found:
                return (model.onSimulator ? "Tap my screen \(app.simulatorWhere)" : "Tap my screen on your desk",
                        "I'm the one holding up “\(Runtime.Greeting.tapMe)”. A tap is also how you poke me, any time.")
            case .trouble(let device): return ("I can't look for my body", device.detail)
            case .none: return ("Looking for my body…", hint)
            }
        }
    }

    // MARK: The hero slot: one tile, one size, in every state

    @ViewBuilder private var hero: some View {
        switch model.body {
        case .intro, .skipped: PlugIn(model: model)
        case .looking:
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero, face: model.stuck ? .stopped : .idle)
                // Rings while looking; none while something stops it.
                .background { if !model.stuck { Ripples().frame(width: Ripples.frame.width, height: Ripples.frame.height) } }
                .overlay(alignment: .bottom) {
                    if case .found(let name) = model.board {
                        Text("FOUND \(name.uppercased())")
                            .font(.detail.weight(.semibold)).tracking(0.6)
                            .foregroundStyle(Theme.sageInk)
                            .padding(.horizontal, Theme.gapSnug).padding(.vertical, Theme.gapTight)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                            // Across the tile's foot.
                            .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .task { await model.beckon() }
                    }
                }
        case .joined:
            ZStack {
                // The on-screen Boop leaps off toward the desk, and leaves:
                // one slime on the page at a time…
                if !(still || flown) {
                    OnboardingBuddy(model: model, snapshot: .onboarding(mood: "excited"), size: ActSize.hero)
                        .transition(.asymmetric(insertion: .identity, removal: .scale(scale: 0.3)
                            .combined(with: .offset(x: 300, y: 120)).combined(with: .opacity)))
                }
                // …and the board on the desk wakes up.
                DeskBoard(model: model)
                    .scaleEffect(still || flown ? 1 : 0.6)
                    .opacity(still || flown ? 1 : 0)
            }
        }
    }

    // MARK: The body

    @ViewBuilder private var content: some View {
        switch model.body {
        case .intro, .skipped:
            if !model.onSimulator {
                VStack(spacing: Theme.gap) {
                    if model.hasLink {
                        Label("macOS will ask if I can use Bluetooth. Say OK, so I can find my body.", systemImage: "info.circle")
                    } else {
                        Text("This copy of Boop runs without a board.")
                    }
                    // No board on the desk: the simulator window will do.
                    if model.hasLink, model.simulatorHere {
                        Button("No board? Use the simulator window", action: model.useSimulator).buttonStyle(ActControlStyle())
                    }
                }
                .font(.note).foregroundStyle(Theme.inkSoft)
            }
        case .looking:
            EmptyView()
        case .joined:
            if let firmware = app.firmwareOffer {
                snack(firmware)
            } else if let device = app.status?.device, !device.hasTheVoice {
                Card(padding: Theme.gutter) {
                    Label("I've lost my voice: there's no voice file on my card. I'll still show everything; Settings says how to fix it.",
                          systemImage: "speaker.slash")
                        .font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: The bar: the main button always there

    private var bar: ActBar {
        let skip = (label: "I don't have my Boop yet", action: { model.skipBoard() })
        // While nothing can look, the way on isn't "no board".
        let onWithout = (label: "Go on without my body for now", action: { model.skipBoard() })
        switch model.body {
        case .intro, .skipped:
            return model.hasLink
                ? ActBar(model: model, next: "Look for me", quiet: skip) { model.lookForBoard() }
                : ActBar(model: model, next: "Next") { model.skipBoard() }
        case .joined:
            return ActBar(model: model)
        case .looking:
            if app.startError != nil {
                return ActBar(model: model, next: "Try again", quiet: onWithout, action: model.startRuntime)
            }
            switch model.board {
            case .trouble(let device):
                if case .system(let label, let url)? = device.fix {
                    return ActBar(model: model, next: label, quiet: onWithout) { NSWorkspace.shared.open(url) }
                }
                return ActBar(model: model, next: onWithout.label, action: onWithout.action)
            case .found: return ActBar(model: model, next: "Waiting for a tap", busy: true, quiet: skip)
            case .none: return ActBar(model: model, next: "Looking…", busy: true, quiet: skip)
            }
        }
    }

    private var hint: String {
        if model.onSimulator {
            return "My window is opening beside this one."
        }
        guard let since = model.lookingSince, Date().timeIntervalSince(since) > Self.hintAfter else {
            return "Keep me plugged in and close by."
        }
        return "Can't see me yet. Is my screen on? Try unplugging me and plugging me back in."
    }

    /// Older firmware than the app carries: a snack, over USB.
    private func snack(_ firmware: BoardFirmware) -> some View {
        Card(padding: Theme.gutter) {
            HStack(spacing: Theme.gap) {
                VStack(alignment: .leading, spacing: Theme.hair) {
                    Text("I'm a bit hungry. Feed me an update?").font(.boopHeading)
                    Text(snackDetail(firmware)).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                switch app.firmwareWrite {
                case .idle, .failed: Button("Update") { app.updateFirmware() }.buttonStyle(ActControlStyle())
                case .writing: ProgressView().controlSize(.small).frame(width: ActSize.controls)
                case .done: Image(systemName: "checkmark.circle.fill").font(.boopTitle).foregroundStyle(Theme.sageSignal)
                        .frame(width: ActSize.controls)
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
    static let cable = CGSize(width: 90, height: 4), plug = CGSize(width: 26, height: 18)

    var body: some View {
        // The tile centred under the title; the cable and plug off its side,
        // out of the layout.
        OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero, face: .asleep)
            .overlay(alignment: .topTrailing) {
                Text("z z")
                    .font(.boopTitle)
                    .foregroundStyle(Theme.inkSoft)
                    .alignmentGuide(.trailing) { $0[.leading] }
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    Capsule().fill(Theme.inkFaint).frame(width: Self.cable.width, height: Self.cable.height)
                    RoundedRectangle(cornerRadius: Theme.chipRadius).fill(Theme.inkSoft)
                        .frame(width: Self.plug.width, height: Self.plug.height)
                        .overlay { Image(systemName: "bolt.fill").font(.detail).foregroundStyle(Theme.paper) }
                }
                .alignmentGuide(.trailing) { $0[.leading] }
            }
            .accessibilityElement()
            .accessibilityLabel("The board, plugged into power, napping")
    }
}

/// The board after the jump: its screen, awake, on a little desk under it,
/// the same size as before so nothing moves.
private struct DeskBoard: View {
    @ObservedObject var model: OnboardingModel
    static let desk = CGSize(width: 280, height: 8)

    var body: some View {
        OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.gapTight).fill(Theme.well)
                    .overlay(RoundedRectangle(cornerRadius: Theme.gapTight).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                    .frame(width: Self.desk.width, height: Self.desk.height)
                    .alignmentGuide(.bottom) { $0[.top] - Theme.gapTight }
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

    /// Its body is here: paired in act 4, or connected after a relaunch
    /// past it (which forgets the pairing, not the board).
    private var paired: Bool { model.hasBoard }

    var body: some View {
        ActFrame(kind: .list, title: "Here's how we get along",
                 lead: paired ? nil : "You'll try these on my body when we meet.",
                 bar: ActBar(model: model, next: "Got it")) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.side)
        } content: {
            VStack(spacing: Theme.gapSnug) {
                lesson(1, "Tap my screen", "I poke back. Tap a lot and I get grumpy.", done: model.lessons.contains(.tap))
                lesson(2, "Press my button", buttonDetail,
                       done: model.lessons.contains(.button), waiting: paired && model.lessons.contains(.tap))
                lesson(3, "Hold my button and talk", talkDetail, done: model.lessons.contains(.talk),
                       waiting: paired && model.lessons.contains(.button))
                trySaying
                lesson(4, "When I glow amber, tap me", amberDetail, done: model.lessons.contains(.amber),
                       waiting: paired && model.lessons.isSuperset(of: [.tap, .button, .talk]), amber: true)
            }
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

    /// The button lesson's words: where the button is, on the board or in
    /// the browser, and what it does.
    private var buttonDetail: String {
        let which = model.onSimulator ? "BOOT, under my screen, or Space." : "The one on my side."
        return which + (paired ? " It opens your next agent, or pokes me. Try it now." : " It opens your next agent, or pokes me when there's none.")
    }

    /// The amber lesson's words: once the first three are done on the
    /// board, it's glowing amber for practice, as if an agent were waiting.
    private var amberDetail: String {
        guard paired, model.lessons.isSuperset(of: [.tap, .button, .talk]), !model.lessons.contains(.amber) else {
            return "An agent is waiting for you. A tap opens it on your Mac; hold \(model.onSimulator ? "a click" : "a finger") on me to put it away."
        }
        return "I'm glowing amber now, as if an agent were waiting. Tap me to answer it."
    }

    /// What talking to Boop is for: a chat, not orders for your agents.
    static let talkFor = "Say hi, cheer me on, tease me, ask about your agents, or tell me to hush. "
        + "I answer with a face and a sign, and often a word."

    /// Things to say, one of each kind Boop answers: a greeting by the
    /// name you just gave it, praise, and a question about every agent,
    /// which opens the board's drawer.
    static func examples(name: String) -> [String] { ["hi \(name)!", "good job!", "how many agents are running?"] }

    /// The name it answers to: the one set up in act 3, else the runtime's.
    private var name: String {
        let set = app.setup.name.trimmingCharacters(in: .whitespaces)
        return set.isEmpty ? app.name : set
    }

    /// The examples, as chips under the talk lesson. A name too long for them
    /// all on a line leaves out the middle one: the window has no room for a
    /// second line, and nothing's cut.
    private var trySaying: some View {
        let examples = Self.examples(name: name)
        let chips = { (words: [String]) in
            HStack(spacing: Theme.gapSnug) {
                Text("TRY").font(.detail.weight(.semibold)).tracking(0.6).foregroundStyle(Theme.inkSoft)
                ForEach(words, id: \.self, content: exampleChip)
            }
        }
        return ViewThatFits(in: .horizontal) {
            chips(examples)
            chips([examples[0], examples[2]])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Under the lesson's title, past its number.
        .padding(.leading, StepRow.indent)
        .accessibilityElement(children: .combine)
    }

    private func exampleChip(_ words: String) -> some View {
        // Words to say aloud, not buttons: no edge.
        Text("“\(words)”").font(.detail).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, Theme.gapSnug).padding(.vertical, Theme.gapTight)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
    }

    /// The talk lesson's words: what it's for, what the Mac heard, or why
    /// it can't hear.
    private var talkDetail: String {
        guard paired else { return Self.talkFor + " Or use Talk on the Mac." }
        if let why = app.status?.micTrouble { return why }
        switch model.talk {
        case .heard(let words): return "I heard “\(Self.quoted(words))”."
        case .nothing: return "I didn't catch that. Keep holding while you talk, then let go."
        case nil: return Self.talkFor + " macOS asks for the microphone the first time."
        }
    }

    /// What was heard, as much as the act's fixed window has room for (three
    /// lines with what follows it), cut short at a word.
    static func quoted(_ words: String, most: Int = 120) -> String {
        guard words.count > most else { return words }
        let cut = words.prefix(most)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    private func lesson(_ number: Int, _ title: String, _ detail: String, done: Bool = false, waiting: Bool = false,
                        amber: Bool = false) -> some View {
        StepRow(number: number, title: title, detail: detail, done: done, waiting: waiting, amber: amber)
    }
}
