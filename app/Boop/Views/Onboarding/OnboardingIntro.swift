import AppKit
import BoopKit
import LinkKit
import SwiftUI

// Acts 1 to 3: hello, what Boop does, and a name.

/// Act 1: Boop drops in, squashes as it lands, and says hi.
struct HelloAct: View {
    @ObservedObject var model: OnboardingModel
    @ViewState private var landed = false
    @ViewState private var squash = false
    @ViewState private var greeted = false
    @Environment(\.stillMotion) private var still
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let calm = still || reduced
        let shown = calm || greeted
        ActFrame(kind: .hero, slot: ActSize.entranceSlot, bar: ActBar(model: model, next: "Hi, Boop!", shown: shown)) {
            // The face at the slot's foot, the bubble up and left of it,
            // its tail toward the face.
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.entrance)
                .scaleEffect(x: squash ? 1.12 : 1, y: squash ? 0.86 : 1, anchor: .bottom)
                .offset(y: calm || landed ? 0 : -360)
                .overlay(alignment: .topLeading) {
                    Bubble("Hi! I'm a Boop.", tailTrailing: true)
                        .fixedSize()
                        .alignmentGuide(.leading) { $0[.trailing] - ActSize.side }
                        .alignmentGuide(.top) { $0[.bottom] - Theme.gap }
                        .scaleEffect(shown ? 1 : 0.2, anchor: .bottomTrailing)
                        .opacity(shown ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
        } content: {
            Text("A little creature for your desk. I keep an eye on your coding agents, and I'll show you how in a couple of minutes.")
                .font(.lead)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: ActSize.lead)
                .opacity(shown ? 1 : 0)
        }
        .task { await arrive(calm: calm) }
    }

    private func arrive(calm: Bool) async {
        guard !calm else { return }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { landed = true }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeOut(duration: 0.08)) { squash = true }
        try? await Task.sleep(for: .milliseconds(90))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { squash = false }
        try? await Task.sleep(for: .milliseconds(700))
        model.feed.poke()
        OnboardingSound.play(.step)
        withAnimation(.boopPop) { greeted = true }
    }
}

/// Act 2: a pretend agent session, and Boop following it live: what its
/// calls touch on Boop's monitor and at the bottom, a failed test hitting
/// it, a request for you, and a finish.
struct WhatIDoAct: View {
    @ObservedObject var model: OnboardingModel
    @ViewState private var step = Step.asking
    /// How many calls the session has made: the board shows each one's word.
    @ViewState private var drops = 0
    /// The beat the demo plays from, and a count of clicks on the cards,
    /// each of which starts it again from there.
    @ViewState private var from = Step.typing
    @ViewState private var clicks = 0
    /// How far the lit card's part has played, 0 to 1, for its bar.
    @ViewState private var played: CGFloat = 0
    @Environment(\.stillMotion) private var still

    /// The pretend session's beats, each with what's on the terminal by then,
    /// Boop's look, and how long it holds.
    enum Step: Int, CaseIterable, Comparable {
        case typing, reading, testing, failing, asking, finished

        var lines: [(String, Color)] {
            let all: [(String, Color)] = [
                ("› fix the flaky login test", Color(hex: Palette.oat)),
                ("Reading auth/session.ts, searching “login”", Color(hex: Palette.inkSoftDark)),
                ("Running npm test", Color(hex: Palette.inkSoftDark)),
                ("✗ 2 tests fail", Color(hex: Palette.clayInkDark)),
                ("Allow edit to auth/session.ts? (y/n)", Color(hex: Palette.amberInkDark)),
                ("✓ 42 tests pass", Color(hex: Palette.sageInkDark)),
            ]
            return Array(all.prefix(rawValue + 1))
        }

        /// The words its agent's calls drop past Boop, one each as the
        /// beat goes on, as the board shows them: a file it read, a word it
        /// searched for, a command; none when it calls nothing.
        var words: [String] {
            switch self {
            case .reading: ["session.ts", "login", "read"]
            case .testing, .failing: ["npm test"]
            case .typing, .asking, .finished: []
            }
        }

        /// Boop's look, with `drops` words fallen so far.
        func look(drops: Int) -> StateSnapshot {
            var look: StateSnapshot = switch self {
            case .typing: .onboarding(doing: "working", activity: Act.typing.rawValue, mood: "curious")
            case .reading: .onboarding(doing: "working", activity: Act.looking.rawValue, mood: "focused")
            case .testing: .onboarding(doing: "working", activity: Act.running.rawValue, mood: "determined")
            case .failing: .onboarding(doing: "working", activity: Act.running.rawValue, mood: "grumpy")
            case .asking: .onboarding(doing: "working", mood: "curious", waiting: "claude")
            case .finished: .onboarding(doing: "idle", mood: "proud")
            }
            if let word = words.last, drops > 0 { look.calls = [.init(slot: 0, count: drops, word: word)] }
            return look
        }

        var seconds: Double {
            switch self {
            case .typing: 2.2
            case .reading: 2.4
            case .testing: 1.8
            case .failing: 3.0
            case .asking: 3.4
            case .finished: 3.6
            }
        }

        /// Which of the three cards it lights.
        var card: Int { self == .asking ? 1 : self == .finished ? 2 : 0 }

        /// The beat a click on card `index` plays from: its first.
        static func first(of index: Int) -> Step { allCases.first { $0.card == index }! }

        /// How long its card stays lit, from its first beat.
        var cardSeconds: Double { Self.allCases.filter { $0.card == card }.map(\.seconds).reduce(0, +) }

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// The demo's tile, 4:3, the engine's own shape, so the "needs you"
    /// sign fits.
    static let tile = CGSize(width: 184, height: 138)

    var body: some View {
        ActFrame(kind: .list, title: "I keep an eye on your agents", bar: ActBar(model: model, next: "Neat!")) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                HStack(spacing: Theme.gapSection) {
                    terminal
                    OnboardingBuddy(model: model, snapshot: step.look(drops: drops), size: Self.tile.width, height: Self.tile.height)
                        .overlay {
                            // Inside the tile's edge, so it stays in the gutter.
                            RoundedRectangle(cornerRadius: Self.tile.height * 0.27)
                                .strokeBorder(Theme.amber, lineWidth: 4)
                                .opacity(step == .asking ? 1 : 0)
                        }
                        .animation(.boopSettle, value: step)
                }
                HStack(alignment: .top, spacing: Theme.gapSnug) {
                    card(0, "Working along", "My monitor shows what your agent is doing, and what it works on. Failures hit me.")
                    card(1, "Needs you", "I glow amber and knock, and say who's waiting.")
                    card(2, "A big finish", "I cheer work that earns it, and hold up whose it was.")
                }
                .fixedSize(horizontal: false, vertical: true)
                MoodLegend()
                    .padding(.top, Theme.gapTight)
                Text("I only watch. I never approve, deny or block anything for you.")
                    .font(.note)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: clicks) { await play() }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: Theme.gapTight) {
            ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                Text(line.0).foregroundStyle(line.1)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            Spacer(minLength: 0)
        }
        .font(.mono)
        .padding(Theme.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.tile.height)
        .terminalCard()
        .animation(.boopSettle, value: step)
    }

    /// A card, lit while the demo shows it, with a bar along its foot
    /// filling as its part plays. A click plays its part now.
    private func card(_ index: Int, _ title: String, _ detail: String) -> some View {
        let lit = step.card == index
        let tone = index == 1 ? Theme.amber : Theme.ink
        return Button {
            from = Step.first(of: index)
            clicks += 1
        } label: {
            Card(tone: lit ? tone : nil) {
                VStack(alignment: .leading, spacing: Theme.gapTight) {
                    Text(title).font(.boopHeading)
                    Text(detail).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // As tall as the row's tallest, so the three line up.
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .animation(.boopSettle, value: step)
            .overlay(alignment: .bottomLeading) {
                if lit, !still {
                    GeometryReader { box in
                        Capsule().fill(tone.opacity(0.55))
                            .frame(width: max(0, box.size.width * played), height: 3)
                    }
                    .frame(height: 3)
                    .padding(.horizontal, Theme.gap).padding(.bottom, Theme.gapTight)
                    .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .help("Show me")
        .accessibilityHint("Plays this part of the demo")
    }

    /// Plays the session's beats over and over, from the one a card's click
    /// asked for, each beat's words showing in turn, the failed test's FAIL
    /// hitting Boop and the finish with Boop's own celebration, until
    /// the act goes. Each card's bar fills over its beats.
    private func play() async {
        guard !still else {
            // Held still, a click only lights its card.
            if clicks > 0 { step = from }
            return
        }
        var start = from
        while !Task.isCancelled {
            for beat in Step.allCases where beat >= start {
                withAnimation(.boopSettle) { step = beat }
                if beat == Step.first(of: beat.card) {
                    // Emptied, drawn so, then filled over the card's beats.
                    played = 0
                    try? await Task.sleep(for: .milliseconds(20))
                    if Task.isCancelled { return }
                    withAnimation(.linear(duration: beat.cardSeconds)) { played = 1 }
                }
                switch beat {
                case .failing: model.feed.call(BoopDevice.call("fail", style: "hail", slot: 0))
                case .asking: OnboardingSound.play(.step)
                case .finished: model.feed.reaction(Moment(anim: "task_complete", outcome: "success"))
                default: break
                }
                // The beat's words, spread over it; the rest of it held.
                let gap = beat.seconds / Double(beat.words.count + 1)
                for _ in beat.words {
                    try? await Task.sleep(for: .seconds(gap))
                    if Task.isCancelled { return }
                    drops += 1
                }
                try? await Task.sleep(for: .seconds(beat.words.isEmpty ? beat.seconds : gap))
                if Task.isCancelled { return }
            }
            start = .typing
        }
    }
}

/// How Boop feels: four of its moods, each with what brings it on, and
/// how a mood moves. Something to read, not cards to pick.
struct MoodLegend: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                Text("HOW I FEEL").font(.detail.weight(.semibold)).tracking(0.6).foregroundStyle(Theme.inkSoft)
                Text("My mood holds steady. Big moments move it, and it settles back with time.")
                    .font(.body).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: Theme.gapSnug) {
                face("happy", "Happy", "it's going well")
                face("grumpy", "Grumpy", "failures pile up")
                face("proud", "Proud", "a big finish")
                face("sad", "Sad", "a long turn fails")
            }
        }
    }

    private func face(_ design: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.gapSnug) {
            MoodTile(mood: design, size: ActSize.side)
                // The glass's edge on dark paper, as the big face has.
                .overlay {
                    if scheme == .dark {
                        RoundedRectangle(cornerRadius: ActSize.side * 0.27, style: .continuous)
                            .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
                    }
                }
            VStack(alignment: .leading, spacing: Theme.hair) {
                Text(title).font(.boopLabel)
                Text(detail).font(.detail).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Act 3: a name, for keeps.
struct MakeMeYoursAct: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var app: AppModel
    @FocusState private var nameFocused: Bool
    @ViewState private var hop = false

    init(model: OnboardingModel) {
        self.model = model
        app = model.app
    }

    private var draft: SetupDraft { app.setup }

    /// The widest name, 23 letters each as wide as a W, with the field's
    /// sides.
    static let field: CGFloat = 492

    private var issue: String? { model.nameError ?? draft.nameIssue }

    /// What the bubble says: a long name on a line of its own.
    private var loved: String {
        let name = draft.trimmedName
        return name.count > 12 ? "\(name)!\nI love it." : "\(name)! I love it."
    }

    var body: some View {
        ActFrame(kind: .hero, title: "What should I be called?",
                 bar: ActBar(model: model, next: "That's me", enabled: draft.canContinueName) { model.saveName() }) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero, face: .idle)
                .offset(y: hop ? -10 : 0)
                // Off the tile's top corner and out of the layout, so a
                // name of any length leaves the tile where it is: the
                // bubble's room, 240 at most, starts just inside the
                // tile's edge, and it grows from there.
                .overlay(alignment: .topLeading) {
                    if !draft.trimmedName.isEmpty, draft.nameIssue == nil {
                        Bubble(loved)
                            .frame(width: 240, alignment: .leading)
                            .offset(x: ActSize.hero - Theme.gapSnug, y: Theme.gapSnug)
                            .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .animation(.boopPop, value: draft.trimmedName.isEmpty)
        } content: {
            VStack(spacing: Theme.gap) {
                TextField("A name", text: Binding(get: { app.setup.name }, set: { app.setup.editName($0) }))
                    .font(.boopTitle)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.gap)
                    .fieldBox(Theme.raised, radius: Theme.cardRadius, focus: $nameFocused)
                    .overlay {
                        if issue != nil {
                            RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.clayInk, lineWidth: 1.5)
                        }
                    }
                    .frame(maxWidth: Self.field)
                    .focused($nameFocused)
                    .onAppear {
                        nameFocused = true
                        // The caret at the end, not the name selected: coming
                        // Back with a name set shows no selection box.
                        DispatchQueue.main.async(execute: Self.caretToEnd)
                    }
                    .onChange(of: nameFocused) {
                        if nameFocused { DispatchQueue.main.async(execute: Self.caretToEnd) }
                    }
                    .onSubmit { model.saveName() }
                    .onChange(of: draft.trimmedName) {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = true }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.12)) { hop = false }
                    }
                VStack(spacing: Theme.gapTight) {
                    Text(issue ?? "My name is for keeps, so pick one you love.")
                        .foregroundStyle(issue != nil ? Theme.clayInk : Theme.inkSoft)
                    // It's public: the world of buddies shows it.
                    if issue == nil {
                        Text("Other buddies in the world will see it too.")
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .font(.note)
                .multilineTextAlignment(.center)
            }
        }
    }

    /// Moves the field editor's caret to the end of its text, wherever a
    /// window is editing one.
    static func caretToEnd() {
        for editor in NSApp.windows.compactMap({ $0.firstResponder as? NSTextView }) where editor.isFieldEditor {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }
}
