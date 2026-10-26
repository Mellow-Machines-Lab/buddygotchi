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
        VStack(spacing: 14) {
            ActTitle(title: model.connected ? "Say hi from your agent" : "Which agents should I watch?",
                     detail: model.connected ? nil : "I listen through their hooks. I never approve, deny or block anything.")
            if model.connected {
                hello
            } else if model.detectedAgents.isEmpty {
                Card(padding: 14) {
                    Text("I can't find Claude Code or Codex on this Mac. Install one, then connect me in Settings.")
                        .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                }
            } else {
                choose
            }
            Spacer(minLength: 0)
            nav
        }
    }

    // MARK: Choosing

    private var choose: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(Agent.allCases, id: \.self) { agent in agentCard(agent) }
            }
            if !app.ownsHooks {
                Text("This copy of Boop leaves the hooks to your everyday Boop. Connect only listens for the hello.")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            } else if !app.installer.clientInPlace {
                Text(AppModel.clientMissing + " Then connect your agents in Settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.clayInk).multilineTextAlignment(.center)
            }
            ForEach(Agent.allCases.filter { app.hookErrors[$0] != nil }, id: \.self) { agent in
                Text("Couldn't connect \(agent.displayName): \(app.hookErrors[agent] ?? "")")
                    .font(.system(size: 12)).foregroundStyle(Theme.clayInk).multilineTextAlignment(.center)
            }
            Button {
                withAnimation(.boopSettle) { model.showHooks.toggle() }
            } label: {
                Label("See exactly what gets added", systemImage: model.showHooks ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.quiet)
            if model.showHooks {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.whatHooksDo, id: \.self) { paragraph in
                            Text(paragraph).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(model.detectedAgents, id: \.self) { agent in additions(agent) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(height: 200)
                .padding(12)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// What the hooks are and what they promise, in words, before the
    /// entries themselves.
    static let whatHooksDo = [
        "Claude Code and Codex can run a small program at moments in a session. I add a hook for each moment I "
            + "follow: a session starting or ending, your prompt, each tool the agent uses, a request for your OK, "
            + "and the agent finishing. Each one runs agent-hook, which tells me here on this Mac what just happened, "
            + "with your prompt, the agent's last reply, and a glimpse of each tool call: the command's name, a file's "
            + "name, a word it searched for, never anything shaped like a key. The glimpses fall past on my screen, "
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                Text(agent.displayName).font(.boop(13, .bold))
                Text(added.file).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft)
            }
            Text("\(added.hooks.count) hooks: " + added.hooks.joined(separator: " · "))
                .font(.system(size: 11, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(added.only, id: \.hook) { only in
                Text("\(only.hook) runs only for \(only.types.joined(separator: ", ")).")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Each one runs").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                Text(added.command).font(.system(size: 11, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(added.also, id: \.self) { also in
                Text(also).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
    }

    private func agentCard(_ agent: Agent) -> some View {
        let found = app.installer.detected(agent)
        let on = found && app.installer.clientInPlace && app.setup.agents.contains(agent)
        return Card(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.displayName).font(.boop(16, .bold))
                    Text(found ? "Found on this Mac" : "Not found on this Mac")
                        .font(.system(size: 12, weight: found ? .semibold : .regular))
                        .foregroundStyle(found ? Theme.sageInk : Theme.inkSoft)
                }
                Spacer()
                Toggle("Watch \(agent.displayName)", isOn: Binding(get: { on }, set: { value in
                    if value { app.setup.agents.insert(agent) } else { app.setup.agents.remove(agent) }
                }))
                .toggleStyle(.boopLarge).labelsHidden()
                .disabled(!found || !app.installer.clientInPlace)
            }
        }
        .opacity(found ? 1 : 0.6)
    }

    // MARK: The live hello

    private var hello: some View {
        let names = Agent.allCases.filter { app.setup.agents.contains($0) && app.installer.detected($0) }.map(\.displayName)
        let which = names.first ?? "Claude Code"
        let heard = model.heard.map { Agent(rawValue: $0)?.displayName ?? which }
        let touring = heard != nil && model.tours
        return VStack(spacing: touring ? 8 : 12) {
            HStack(spacing: 18) {
                // After the hello, the board's own state, so your agent's
                // words fall past it here too.
                OnboardingBuddy(model: model, snapshot: heard == nil ? .onboarding(mood: "curious") : model.live,
                                size: touring ? 84 : 104)
                VStack(alignment: .leading, spacing: 5) {
                    Text(heard == nil ? "Open a new \(which) session, and ask it to list the files here" : "Heard you!")
                        .font(.boop(17, .bold)).foregroundStyle(Color(hex: Palette.inkDark))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(heard.map { "\($0) is connected." + (touring ? " Now let me show you around." : " I'll be watching.") }
                        ?? "I'll wave when your agent's first hook reaches me.")
                        .font(.system(size: 13)).foregroundStyle(Color(hex: Palette.inkSoftDark))
                    if heard != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: Palette.sageInkDark))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(touring ? 14 : 18)
            .terminalCard()
            .animation(.boopPop, value: model.heard)
            ForEach(Agent.allCases.filter { app.hookErrors[$0] != nil }, id: \.self) { agent in
                Text("Couldn't connect \(agent.displayName): \(app.hookErrors[agent] ?? "")")
                    .font(.system(size: 12)).foregroundStyle(Theme.clayInk)
            }
            if touring {
                tourSteps
            } else if heard != nil {
                Text("The words falling past me are what your agent works on: its files, searches and commands. Once we're done, click any agent in my menu up top to jump to its thread.")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sessions already open need a restart to pick up my hooks.")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            }
        }
        // The tour's first step: your agent's words falling past Boop.
        .onChange(of: model.wordsFalling, initial: true) { _, falling in
            if falling, model.tours { model.sawWords() }
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
        return VStack(spacing: 6) {
            step(.words, "Watch my screen", model.tour.contains(.words)
                 ? "Those words are what your agent works on: the files it reads, its searches and commands."
                 : "What your agent works on falls past me as words. Nothing yet? Ask it to list the files here.")
            step(.cheer, "When I cheer, tap me", due == .cheer && model.finishedThread == nil
                 ? "When your agent finishes, I cheer and hold up its thread's name. A tap takes you there."
                 : "Your agent finished. A tap takes you to its thread.")
            step(.drawer, model.onSimulator ? "Drag up from my bottom edge" : "Swipe up from my bottom edge", "Every agent you have open is in there.")
            step(.row, "Tap your thread", "It opens right where it runs. That's how you get back to any of them.")
        }
    }

    @ViewBuilder private var nav: some View {
        if model.connected {
            // Until an agent says hi, moving on is "later"; after, on a board
            // that tours, the tour comes first.
            // The tour waits on the board and the agent (a turn to finish,
            // the drawer), so it can always be skipped.
            let mayLeave = model.progress.mayLeaveAgents(tours: model.tours)
            let skip: (label: String, action: () -> Void)? = mayLeave ? nil : (label: "Skip the tour", action: { model.next() })
            ActNav(model: model, next: model.heard == nil ? "I'll try it later" : "Next", enabled: mayLeave, quiet: skip)
        } else if model.detectedAgents.isEmpty || !app.installer.clientInPlace {
            ActNav(model: model)
        } else {
            ActNav(model: model, next: "Connect", enabled: !app.setup.agents.isEmpty) { model.connectAgents() }
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
        VStack(spacing: 12) {
            ActTitle(title: "A few small things")
            login
            if model.askMic { mic }
            OnboardingBrainKey(app: app, hasBoard: model.hasBoard)
            Spacer(minLength: 0)
            ActNav(model: model)
        }
    }

    private var login: some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("I'll be here when you log in", systemImage: "power").font(.boop(15, .bold))
                    Text(loginDetail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if app.loginItemState == .needsApproval {
                    Button("Open") { NSWorkspace.shared.open(LoginItem.settingsURL) }.buttonStyle(.row)
                } else {
                    Toggle("Open at login", isOn: Binding(get: { app.loginItemState == .on }, set: {
                        model.loginTouched = true
                        app.setOpenAtLogin($0)
                    }))
                    .toggleStyle(.boopLarge).labelsHidden()
                    .disabled(app.loginItemState == .unavailable)
                }
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
        Card(padding: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Want to talk to me?", systemImage: "mic").font(.boop(15, .bold))
                    Text(micDetail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                switch model.mic {
                case .notAsked: Button("Allow") { model.askForMic() }.buttonStyle(.row)
                case .asking: ProgressView().controlSize(.small)
                case .allowed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                case .refused: EmptyView()
                }
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
        VStack(spacing: 16) {
            OnboardingBuddy(model: model, snapshot: .onboarding(mood: "excited"), size: 150)
                .rotationEffect(.degrees(-4))
                .padding(.top, 6)
            Text("\(model.name) is all set!").font(.boop(30, .heavy))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if model.hasBoard {
                    tip("mic", model.onSimulator ? "Hold BOOT, or Space" : "Hold my button", "and ask how your agents are doing")
                    tip("bell", "Amber, or cheering?", "Tap me to open that thread", amber: true)
                    // Everyone finds the poke; nobody finds the drawer.
                    if model.tours {
                        tip("rectangle.bottomhalf.inset.filled", model.onSimulator ? "Drag up from the bottom" : "Swipe up from the bottom",
                            "for every agent; tap one to open it")
                    } else {
                        tip("hand.tap", "Tap my screen", "to poke me")
                    }
                } else {
                    tip("powerplug", "Got my body?", "plug it in, and I'll find it")
                    tip("mic", "Click Talk", "in my menu, and ask how your agents are doing")
                    tip("bell", "Amber? Click me", "up top, to see who's waiting", amber: true)
                }
                tip("menubar.arrow.up.rectangle", "Find me", "in the menu bar, up top")
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
            Button("Let's go!") { model.finish() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .task { model.feed.reaction(DeviceReaction(anim: "task_complete", outcome: "success")) }
    }

    /// A tip; amber's, which is what it means, has its dot.
    private func tip(_ icon: String, _ title: String, _ detail: String, amber: Bool = false) -> some View {
        Card(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).font(.boop(14, .bold))
                        if amber { StateDot(tone: Theme.amber) }
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
