import AgentHooks
import BoopKit
import SwiftUI

// Acts 6 to 8: the agents, a few small things, and the finale.

/// Act 6: which agents to watch, then a live hello from one of them, which
/// proves the hooks reach Boop.
struct AgentsAct: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var app: AppModel

    init(model: OnboardingModel) {
        self.model = model
        app = model.app
    }

    var body: some View {
        // Once connected, the hello card holds the face: one slime on the
        // page at a time.
        ActFrame(kind: .list, title: model.connected ? "Say hi from your agent" : "Which agents should I watch?",
                 lead: model.connected ? nil : "I listen through their hooks. I never approve, deny or block anything.",
                 faced: !model.connected, bar: bar) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.side, face: .happy)
        } content: {
            if model.connected {
                hello
            } else if model.detectedAgents.isEmpty {
                Card(padding: Theme.gutter) {
                    Text("I can't find Claude Code or Codex on this Mac. Install one, then connect me in Settings.")
                        .font(.note).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                choose
            }
        }
    }

    // MARK: Choosing

    private var choose: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(spacing: Theme.gap) {
                ForEach(Agent.allCases, id: \.self) { agent in agentCard(agent) }
            }
            Group {
                if !app.ownsHooks {
                    Text("This copy of Boop leaves the hooks to your everyday Boop. Connect only listens for the hello.")
                        .foregroundStyle(Theme.inkSoft)
                } else if !app.installer.clientInPlace {
                    Text(AppModel.clientMissing + " Then connect your agents in Settings.")
                        .foregroundStyle(Theme.clayInk)
                }
                ForEach(Agent.allCases.filter { app.hookErrors[$0] != nil }, id: \.self) { agent in
                    Text("Couldn't connect \(agent.displayName): \(app.hookErrors[agent] ?? "")")
                        .foregroundStyle(Theme.clayInk)
                }
            }
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(.boopSettle) { model.showHooks.toggle() }
            } label: {
                HStack(spacing: Theme.gapTight) {
                    Image(systemName: model.showHooks ? "chevron.down" : "chevron.right").foregroundStyle(Theme.ink)
                    Text("See exactly what gets added")
                }
                .font(.note)
            }
            .buttonStyle(.quiet)
            .padding(.leading, -Theme.gapSnug)
            if model.showHooks { hooks }
        }
    }

    /// The hooks, agent by agent, then what they are in words: a panel that
    /// scrolls, with a fade at its foot and no scroller.
    private var hooks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(model.detectedAgents, id: \.self) { agent in additions(agent) }
                ForEach(Self.whatHooksDo, id: \.self) { paragraph in
                    Text(paragraph).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: ActSize.heroBody, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.gap)
            .textSelection(.enabled)
        }
        .scrollIndicators(.never)
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: ActSize.fade)
            }
        }
        .frame(height: ActSize.panel)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// What the hooks are and what they promise, in words, before the
    /// entries themselves.
    static let whatHooksDo = [
        "Claude Code and Codex can run a small program at moments in a session. I add a hook for each moment I "
            + "follow: a session starting or ending, your prompt, each tool the agent uses, a request for your OK, "
            + "and the agent finishing. Each one runs agent-hook, which tells me here on this Mac what just happened, "
            + "with your prompt, the agent's last reply, and a glimpse of each tool call: the command's name, a file's "
            + "name, a word it searched for, never anything shaped like a key. The newest shows at the bottom of my screen, "
            + "where anyone at your desk can read them. My brain only ever hears a short reading of your prompt and the "
            + "reply, never your code or the glimpses.",
        "Hooks only report: they never approve, deny or block anything, and when I'm not running, your agent "
            + "carries on as usual. Your other hooks stay as they are, I keep a copy of each file before I change it, "
            + "and Uninstall in Settings takes mine out.",
    ]

    /// One agent's entries: the file, its hooks, the ones that run only
    /// for some types, the command every one runs, and anything else that
    /// changes.
    private func additions(_ agent: Agent) -> some View {
        let added = Additions(app.installer, agent)
        return VStack(alignment: .leading, spacing: Theme.gapTight) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                Text(agent.displayName).font(.boopLabel)
                Text(added.file).font(.mono).foregroundStyle(Theme.inkSoft)
            }
            Text("\(added.hooks.count) hooks: " + added.hooks.joined(separator: " · "))
                .font(.mono)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(added.only, id: \.hook) { only in
                Text("\(only.hook) runs only for \(only.types.joined(separator: ", ")).")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.hair) {
                Text("Each one runs").caption()
                Text(added.command).font(.mono)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(added.also, id: \.self) { also in
                Text(also).caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
    }

    /// An agent: found, with its switch; not found, said plainly, with no
    /// switch to fade.
    private func agentCard(_ agent: Agent) -> some View {
        let found = app.installer.detected(agent)
        let on = found && app.installer.clientInPlace && app.setup.agents.contains(agent)
        return Card(padding: Theme.gutter) {
            HStack(spacing: Theme.gap) {
                VStack(alignment: .leading, spacing: Theme.hair) {
                    Text(agent.displayName).font(.boopHeading)
                    Text(found ? "Found on this Mac" : "Not found on this Mac")
                        .font(found ? .bodyStrong : .body)
                        .foregroundStyle(found ? Theme.sageInk : Theme.inkSoft)
                }
                Spacer(minLength: 0)
                Group {
                    if found {
                        Toggle("Watch \(agent.displayName)", isOn: Binding(get: { on }, set: { value in
                            if value { app.setup.agents.insert(agent) } else { app.setup.agents.remove(agent) }
                        }))
                        .toggleStyle(.boopLarge).labelsHidden()
                        .disabled(!app.installer.clientInPlace)
                    } else {
                        Chip("Not installed")
                    }
                }
                .frame(height: ActSize.control)
            }
        }
    }

    // MARK: The live hello

    private var hello: some View {
        let names = Agent.allCases.filter { app.setup.agents.contains($0) && app.installer.detected($0) }.map(\.displayName)
        let which = names.first ?? "Claude Code"
        let heard = model.heard.map { Agent(rawValue: $0)?.displayName ?? which }
        let touring = heard != nil && model.tours
        return VStack(spacing: touring ? Theme.gapSnug : Theme.gap) {
            HStack(spacing: Theme.gapSection) {
                // After the hello, the board's own state, so your agent's
                // work shows on it here too.
                OnboardingBuddy(model: model, snapshot: heard == nil ? .onboarding(mood: "curious") : model.live,
                                size: touring ? Self.touringFace : Self.helloFace)
                    // On the dark card the glass needs its edge in either appearance.
                    .overlay(RoundedRectangle(cornerRadius: (touring ? Self.touringFace : Self.helloFace) * 0.27)
                        .strokeBorder(Theme.terminalEdge, lineWidth: 1))
                VStack(alignment: .leading, spacing: Theme.gapTight) {
                    Text(heard == nil ? "Open a new \(which) session, and ask it to list the files here" : "Heard you!")
                        .font(.boopTitle).foregroundStyle(Color(hex: Palette.inkDark))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(heard.map { "\($0) is connected." + (touring ? " Now let me show you around." : " I'll be watching.") }
                        ?? "I'll wave when your agent's first hook reaches me.")
                        .font(.note).foregroundStyle(Color(hex: Palette.inkSoftDark))
                    if heard != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.bodyStrong).foregroundStyle(Color(hex: Palette.sageInkDark))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(touring ? Theme.gap : Theme.gapSection)
            .terminalCard()
            .animation(.boopPop, value: model.heard)
            ForEach(Agent.allCases.filter { app.hookErrors[$0] != nil }, id: \.self) { agent in
                Text("Couldn't connect \(agent.displayName): \(app.hookErrors[agent] ?? "")")
                    .font(.body).foregroundStyle(Theme.clayInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if touring {
                tourSteps
            } else if heard != nil {
                Text("My little monitor shows what your agent is doing, and the word at the bottom is what it works on: a file, a search, a command. Once we're done, click any agent in my menu up top to jump to its thread.")
                    .font(.body).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sessions already open need a restart to pick up my hooks.")
                    .font(.body).foregroundStyle(Theme.inkSoft)
            }
        }
        // The tour's first step: your agent's work showing on Boop.
        .onChange(of: model.wordsShowing, initial: true) { _, showing in
            if showing, model.tours { model.sawWords() }
        }
        // Its second: Boop cheers for the finished turn until it's tapped.
        .task(id: model.tours && model.tourDue == .cheer) {
            if model.tours, model.tourDue == .cheer { await model.cheer() }
        }
    }

    // MARK: The tour

    /// What the tour asks of you on the board, a step at a time: each is
    /// done there, and the window ticks it.
    private var tourSteps: some View {
        let due = model.tourDue
        func step(_ step: Onboarding.Progress.Tour, _ title: String, _ detail: String) -> some View {
            StepRow(number: step.rawValue + 1, title: title, detail: detail, done: model.tour.contains(step),
                    waiting: due == step, compact: true)
        }
        return VStack(spacing: Theme.gapTight) {
            step(.words, "Watch my screen", model.tour.contains(.words)
                 ? "My monitor shows what your agent is doing, and the word at the bottom is what it works on."
                 : "What your agent works on shows on my monitor and at the bottom. Nothing yet? Ask it to list the files here.")
            step(.cheer, "When I cheer, tap me", due == .cheer && model.finishedThread == nil
                 ? "When your agent finishes, I cheer and hold up its thread's name. A tap takes you there."
                 : "Your agent finished. A tap takes you to its thread.")
            step(.drawer, model.onSimulator ? "Drag up from my bottom edge" : "Swipe up from my bottom edge", "Every agent you have open is in there.")
            step(.row, "Tap your thread", "It opens right where it runs. That's how you get back to any of them.")
        }
    }

    /// The hello card's face, and the smaller one while it tours.
    static let helloFace: CGFloat = 104, touringFace: CGFloat = SlimeFace.zoomBelow

    private var bar: ActBar {
        if model.connected {
            // Until an agent says hi, moving on is "later"; after, on a board
            // that tours, the tour comes first.
            // The tour waits on the board and the agent (a turn to finish,
            // the drawer), so it can always be skipped.
            let mayLeave = model.progress.mayLeaveAgents(tours: model.tours)
            let skip: (label: String, action: () -> Void)? = mayLeave ? nil : (label: "Skip the tour", action: { model.next() })
            return ActBar(model: model, next: model.heard == nil ? "I'll try it later" : "Next", enabled: mayLeave, quiet: skip)
        } else if model.detectedAgents.isEmpty || !app.installer.clientInPlace {
            return ActBar(model: model)
        } else {
            return ActBar(model: model, next: "Connect", enabled: !app.setup.agents.isEmpty) { model.connectAgents() }
        }
    }
}

/// What installing adds for an agent, as the installer's preview says it:
/// a line per hook, `Hook (types) → command`, then, after a blank line,
/// what else changes (Codex's switch). Paths start at `~`.
struct Additions {
    var file: String
    var hooks: [String] = []
    /// The hooks that run only for some types, and which.
    var only: [(hook: String, types: [String])] = []
    var command: String
    var also: [String] = []

    init(_ installer: HookInstaller, _ agent: Agent) {
        func home(_ text: String) -> String { text.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        file = home(installer.configURL(agent).path)
        command = home(installer.command(agent))
        var paragraphs = installer.preview(agent).components(separatedBy: "\n\n")
        let lines = paragraphs.isEmpty ? [] : paragraphs.removeFirst().components(separatedBy: "\n")
        let runs = " → " + installer.command(agent)
        for line in lines {
            let hook = line.hasSuffix(runs) ? String(line.dropLast(runs.count)) : line
            if let open = hook.range(of: " ("), hook.hasSuffix(")") {
                let name = String(hook[..<open.lowerBound])
                hooks.append(name)
                only.append((name, hook[open.upperBound...].dropLast().components(separatedBy: "|")))
            } else {
                hooks.append(hook)
            }
        }
        also = paragraphs.map(home)
    }
}

/// Act 7: opening at login, the microphone, unless act 5's push-to-talk
/// had it allowed, and the brain's key, each one card and each skippable.
struct SmallThingsAct: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var app: AppModel

    init(model: OnboardingModel) {
        self.model = model
        app = model.app
    }

    var body: some View {
        ActFrame(kind: .list, title: "A few small things", bar: ActBar(model: model)) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.side, face: .happy)
        } content: {
            VStack(spacing: Theme.gapSnug) {
                login
                if model.askMic { mic }
                OnboardingBrainKey(app: app, hasBoard: model.hasBoard, saved: model.keySaved)
            }
        }
    }

    private var login: some View {
        SmallThing("I'll be here when you log in", icon: "power", detail: loginDetail) {
            if app.loginItemState == .needsApproval {
                Button("Open") { NSWorkspace.shared.open(LoginItem.settingsURL) }.buttonStyle(ActControlStyle())
            } else if app.loginItemState == .unavailable {
                // It can't be switched here: the detail says why, and no
                // dead switch stands beside it.
                Color.clear
            } else {
                Toggle("Open at login", isOn: Binding(get: { app.loginItemState == .on }, set: {
                    model.loginTouched = true
                    app.setOpenAtLogin($0)
                }))
                .toggleStyle(.boopLarge).labelsHidden()
            }
        }
        // Back from System Settings, where Open sent you to allow it.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshLoginItem()
        }
    }

    private var loginDetail: String {
        if let why = app.loginItemError { return "Couldn't change it: \(why)" }
        return switch app.loginItemState {
        case .on, .off: "I only watch your agents while I'm open."
        case .needsApproval: "Allow me in System Settings, under General, Login Items."
        case .unavailable: "Only Boop.app can open at login, and this copy runs from a terminal."
        }
    }

    private var mic: some View {
        SmallThing("Want to talk to me?", icon: "mic", detail: micDetail) {
            switch model.mic {
            case .notAsked: Button("Allow") { model.askForMic() }.buttonStyle(ActControlStyle())
            case .asking: ProgressView().controlSize(.small)
            case .allowed: Image(systemName: "checkmark.circle.fill").font(.boopTitle).foregroundStyle(Theme.sage)
            case .refused: Color.clear
            }
        }
    }

    private var micDetail: String {
        switch model.mic {
        case .refused(let why): why
        case .allowed: "All set: hold my button, or press Talk, and speak."
        default: "macOS will ask for the microphone and speech. Your voice stays on this Mac; only the words, cut short, reach my brain."
        }
    }
}

/// Act 8: a celebration, on screen and on the board, the four ways to
/// reach Boop worth remembering, and off to the menu bar. Without a board,
/// the Mac's way of each, and that the board is found once it's plugged in.
struct FinaleAct: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ActFrame(kind: .hero, title: "\(model.name) is all set!",
                 bar: ActBar(model: model, next: "Let's go!") { model.finish() }) {
            OnboardingBuddy(model: model, snapshot: model.look, size: ActSize.hero)
                .rotationEffect(.degrees(-4))
        } content: {
            VStack(spacing: Theme.gapSnug) {
                ForEach(Array(stride(from: 0, to: tips.count, by: 2)), id: \.self) { row in
                    HStack(alignment: .top, spacing: Theme.gapSnug) {
                        ForEach(tips[row..<min(row + 2, tips.count)], id: \.title) { tip($0) }
                    }
                    // Both tips of a row as tall as the taller.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { model.feed.reaction(Moment(anim: "task_complete", outcome: "success")) }
    }

    private struct Tip {
        var icon: String, title: String, detail: String, amber = false
    }

    /// The four ways to reach Boop worth remembering: the board's, or the
    /// Mac's without one.
    private var tips: [Tip] {
        var tips: [Tip]
        if model.hasBoard {
            tips = [Tip(icon: "mic", title: model.onSimulator ? "Hold BOOT, or Space" : "Hold my button", detail: "and ask how your agents are doing"),
                    Tip(icon: "bell", title: "Amber, or cheering?", detail: "Tap me to open that thread", amber: true)]
            // Everyone finds the poke; nobody finds the drawer.
            tips.append(model.tours
                ? Tip(icon: "rectangle.bottomhalf.inset.filled", title: model.onSimulator ? "Drag up from the bottom" : "Swipe up from the bottom",
                      detail: "for every agent; tap one to open it")
                : Tip(icon: "hand.tap", title: "Tap my screen", detail: "to poke me"))
        } else {
            tips = [Tip(icon: "powerplug", title: "Got my body?", detail: "plug it in, and I'll find it"),
                    Tip(icon: "mic", title: "Click Talk", detail: "in my menu, and ask how your agents are doing"),
                    Tip(icon: "bell", title: "Amber? Click me", detail: "up top, to see who's waiting", amber: true)]
        }
        return tips + [Tip(icon: "menubar.arrow.up.rectangle", title: "Find me", detail: "in the menu bar, up top")]
    }

    /// A tip; amber's, which is what it means, has its dot.
    private func tip(_ tip: Tip) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.gapSnug) {
                Image(systemName: tip.icon).font(.lead.weight(.medium)).foregroundStyle(Theme.ink)
                    .frame(width: Theme.target, height: Theme.target)
                VStack(alignment: .leading, spacing: Theme.hair) {
                    HStack(spacing: Theme.gapSnug) {
                        Text(tip.title).font(.boopHeading)
                        if tip.amber { StateDot(tone: Theme.amber) }
                    }
                    Text(tip.detail).font(.body).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// One of act 7's small things: its title and why, and its control in the
/// column every card shares, so they line up down the act.
struct SmallThing<Control: View>: View {
    let title: String
    let icon: String
    let detail: String
    @ViewBuilder var control: Control

    init(_ title: String, icon: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        Card(padding: Theme.gutter) {
            HStack(spacing: Theme.gap) {
                VStack(alignment: .leading, spacing: Theme.hair) {
                    Label(title, systemImage: icon).font(.boopHeading)
                    Text(detail).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                control.frame(width: ActSize.controls, height: ActSize.control)
            }
        }
    }
}
