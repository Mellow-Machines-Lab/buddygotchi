import BoopKit
import LinkKit
import SwiftUI

// Acts 1 to 3: hello, what Boop does, and a name and a nature.

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
        .padding(.horizontal, 60)
        .padding(.bottom, 30)
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
        model.feed.reaction(id: 0, DeviceReaction(anim: "poked"))
        OnboardingSound.play(.step)
        withAnimation(.boopPop) { greeted = true }
    }
}

/// Act 2: a pretend agent session, and Boop following it live.
struct WhatIDoAct: View {
    @ObservedObject var model: OnboardingModel
    @ViewState private var step = Step.asking
    @Environment(\.stillMotion) private var still

    /// The pretend session's beats, each with what's on the terminal by then,
    /// Boop's look, and how long it holds.
    enum Step: Int, CaseIterable {
        case typing, reading, asking, testing, finished

        var lines: [(String, Color)] {
            let all: [(String, Color)] = [
                ("› fix the flaky login test", Color(hex: Palette.oat)),
                ("Reading auth/session.ts", Color(hex: Palette.inkSoftDark)),
                ("Allow edit to auth/session.ts? (y/n)", Color(hex: Palette.amberInkDark)),
                ("Running npm test", Color(hex: Palette.inkSoftDark)),
                ("✓ 42 tests pass", Color(hex: Palette.sageInkDark)),
            ]
            return Array(all.prefix(rawValue + 1))
        }

        var look: StateSnapshot {
            switch self {
            case .typing: .onboarding(base: "working", act: "planning", mood: "curious")
            case .reading: .onboarding(base: "working", act: "analyzing", mood: "engaged")
            case .asking: .onboarding(base: "working", mood: "curious", waiting: "claude")
            case .testing: .onboarding(base: "working", act: "testing", mood: "determined")
            case .finished: .onboarding(base: "idle", mood: "proud")
            }
        }

        var seconds: Double {
            switch self {
            case .typing: 2.2
            case .reading: 2.4
            case .asking: 3.4
            case .testing: 2.2
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
                OnboardingBuddy(model: model, snapshot: step.look, size: 178)
                    .overlay {
                        RoundedRectangle(cornerRadius: 178 * 0.27 + 6)
                            .strokeBorder(Theme.amber, lineWidth: 5)
                            .padding(-6)
                            .opacity(step == .asking ? 1 : 0)
                    }
                    .animation(.boopSettle, value: step)
            }
            HStack(spacing: 10) {
                card(0, "Working along", "Tests, the terminal, planning: I follow along.")
                card(1, "Needs you", "I glow amber and knock, and say who's waiting.")
                card(2, "A big finish", "I celebrate work that earns it. A failed test? I grumble.")
            }
            Text("I only watch. I never approve, deny or block anything for you.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
            ActNav(model: model, next: "Neat!")
        }
        .padding(.horizontal, 48)
        .padding(.top, 2)
        .padding(.bottom, 30)
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
        .background(Color(hex: Palette.paperDark), in: RoundedRectangle(cornerRadius: 14))
        .animation(.boopSettle, value: step)
    }

    private func card(_ index: Int, _ title: String, _ detail: String) -> some View {
        OnboardingCard(highlight: step.card == index ? (index == 1 ? Theme.amber : Theme.ink) : nil) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.boop(14, .bold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.boopSettle, value: step)
    }

    /// Plays the session's beats over and over, the finish with Boop's own
    /// celebration, until the act goes.
    private func play() async {
        guard !still else { return }
        while !Task.isCancelled {
            for beat in Step.allCases {
                withAnimation(.boopSettle) { step = beat }
                if beat == .finished { model.feed.reaction(id: 0, DeviceReaction(anim: "task_complete", outcome: "success")) }
                if beat == .asking { OnboardingSound.play(.step) }
                try? await Task.sleep(for: .seconds(beat.seconds))
                if Task.isCancelled { return }
            }
        }
    }
}

/// Act 3: a name for keeps, and sweet or cheeky, each shown in how that
/// Boop talks.
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
            ZStack(alignment: .topTrailing) {
                OnboardingBuddy(model: model, snapshot: .onboarding(mood: draft.nature == .cheeky ? "proud" : "happy"), size: 108,
                                face: draft.nature == .cheeky ? .cheeky : .happy)
                    .offset(y: hop ? -10 : 0)
                if !draft.trimmedName.isEmpty, draft.nameIssue == nil {
                    Bubble("\(draft.trimmedName)! I love it.")
                        .offset(x: 140, y: -6)
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
            Text(model.nameError ?? draft.nameIssue ?? "Names are for keeps, so pick one you love.")
                .font(.system(size: 12))
                .foregroundStyle(model.nameError != nil || draft.nameIssue != nil ? Theme.clayInk : Theme.inkSoft)
            Text("Sweet or cheeky?").font(.boop(15, .bold)).padding(.top, 4)
            HStack(spacing: 10) {
                nature(.sweet, "Sweet", "“You did it! Tests are green.”")
                nature(.cheeky, "Cheeky", "“Green, finally. Took you long enough.”")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 480)
            Spacer(minLength: 0)
            ActNav(model: model, next: "That's me", enabled: draft.canContinueName) { model.saveName() }
        }
        .padding(.horizontal, 48)
        .padding(.top, 6)
        .padding(.bottom, 30)
    }

    private func nature(_ nature: LongTerm.Nature, _ title: String, _ line: String) -> some View {
        let on = draft.nature == nature
        return Button {
            withAnimation(.boopPop) { app.setup.nature = nature }
            OnboardingSound.play(.step)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.boop(15, .bold))
                Text(line).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(on ? Theme.paper : Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.ink : Theme.hairline, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
