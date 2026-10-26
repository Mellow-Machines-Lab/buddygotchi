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
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            ZStack(alignment: .topLeading) {
                OnboardingBuddy(model: model, snapshot: .onboarding(mood: "happy"), size: 196)
                    .scaleEffect(x: squash ? 1.12 : 1, y: squash ? 0.86 : 1, anchor: .bottom)
                    .offset(y: calm || landed ? 0 : -360)
                Bubble("Hi! I'm a Boop.")
                    .offset(x: -96, y: -42)
                    .scaleEffect(calm || greeted ? 1 : 0.2, anchor: .bottomTrailing)
                    .opacity(calm || greeted ? 1 : 0)
            }
            .padding(.top, 30)
            Text("A little creature for your desk. I keep an eye on your coding agents, and I'll show you how in a couple of minutes.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .opacity(calm || greeted ? 1 : 0)
            Button("Hi, Boop!") { model.next() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .opacity(calm || greeted ? 1 : 0)
            Spacer(minLength: 0)
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
/// calls touch falling past Boop as words, a failed test hitting it, a
/// request for you, and a finish.
struct WhatIDoAct: View {
    @ObservedObject var model: OnboardingModel
    @ViewState private var step = Step.asking
    /// How many words have fallen: the board drops one for each new call.
    @ViewState private var drops = 0
    @Environment(\.stillMotion) private var still

    /// The pretend session's beats, each with what's on the terminal by then,
    /// Boop's look, and how long it holds.
    enum Step: Int, CaseIterable {
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
            case .typing: .onboarding(base: "working", act: "planning", mood: "curious")
            case .reading: .onboarding(base: "working", act: "analyzing", mood: "engaged")
            case .testing: .onboarding(base: "working", act: "testing", mood: "determined")
            case .failing: .onboarding(base: "working", act: "testing", mood: "grumpy")
            case .asking: .onboarding(base: "working", mood: "curious", waiting: "claude")
            case .finished: .onboarding(base: "idle", mood: "proud")
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
    }

    var body: some View {
        VStack(spacing: 18) {
            ActTitle(title: "I keep an eye on your agents")
            HStack(spacing: 22) {
                terminal
                // 4:3, the engine's own shape, so the "needs you" sign fits.
                OnboardingBuddy(model: model, snapshot: step.look(drops: drops), size: 236, height: 177)
                    .overlay {
                        RoundedRectangle(cornerRadius: 177 * 0.27 + 6)
                            .strokeBorder(Theme.amber, lineWidth: 5)
                            .padding(-6)
                            .opacity(step == .asking ? 1 : 0)
                    }
                    .animation(.boopSettle, value: step)
            }
            HStack(spacing: 10) {
                card(0, "Working along", "The files, searches and commands of your agent fall past me. Failures hit me.")
                card(1, "Needs you", "I glow amber and knock, and say who's waiting.")
                card(2, "A big finish", "I cheer work that earns it, and hold up whose it was.")
            }
            Text("I only watch. I never approve, deny or block anything for you.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
            ActNav(model: model, next: "Neat!")
        }
        .task { await play() }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                Text(line.0).foregroundStyle(line.1)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 178)
        .terminalCard()
        .animation(.boopSettle, value: step)
    }

    private func card(_ index: Int, _ title: String, _ detail: String) -> some View {
        Card(padding: 14, tone: step.card == index ? (index == 1 ? Theme.amber : Theme.ink) : nil) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.boop(14, .bold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.boopSettle, value: step)
    }

    /// Plays the session's beats over and over, each beat's words falling
    /// in turn, the failed test's FAIL raining on Boop and the finish with
    /// Boop's own celebration, until the act goes.
    private func play() async {
        guard !still else { return }
        while !Task.isCancelled {
            for beat in Step.allCases {
                withAnimation(.boopSettle) { step = beat }
                switch beat {
                case .failing: model.feed.call(BoopDevice.call("FAIL", gag: "hail", slot: 0))
                case .asking: OnboardingSound.play(.step)
                case .finished: model.feed.reaction(DeviceReaction(anim: "task_complete", outcome: "success"))
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
        }
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

    var body: some View {
        VStack(spacing: 14) {
            OnboardingBuddy(model: model, snapshot: .onboarding(mood: "happy"), size: 108, face: .happy)
                .offset(y: hop ? -10 : 0)
                // Off the tile's top corner and out of the layout, so a
                // name of any length leaves the tile where it is: the
                // bubble's room, 240 at most, starts just inside the
                // tile's edge, and it grows from there.
                .overlay(alignment: .topTrailing) {
                    if !draft.trimmedName.isEmpty, draft.nameIssue == nil {
                        Bubble("\(draft.trimmedName)! I love it.")
                            .frame(width: 240, alignment: .leading)
                            .offset(x: 240 - Theme.gapSnug, y: -6)
                            .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .animation(.boopPop, value: draft.trimmedName.isEmpty)
            ActTitle(title: "What should I be called?")
            TextField("A name", text: Binding(get: { app.setup.name }, set: { app.setup.editName($0) }))
                .font(.boop(20, .bold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.vertical, 11)
                .fieldBox(Theme.raised, radius: 12, focus: $nameFocused)
                .frame(maxWidth: 360)
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit { model.saveName() }
                .onChange(of: draft.trimmedName) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = true }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.12)) { hop = false }
                }
            Text(model.nameError ?? draft.nameIssue ?? "My name is for keeps, so pick one you love.")
                .font(.system(size: 12))
                .foregroundStyle(model.nameError != nil || draft.nameIssue != nil ? Theme.clayInk : Theme.inkSoft)
            Spacer(minLength: 0)
            ActNav(model: model, next: "That's me", enabled: draft.canContinueName) { model.saveName() }
        }
    }

}
