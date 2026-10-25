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
            Button {
                withAnimation(.boopSettle) { model.showHooks.toggle() }
            } label: {
                Label("See exactly what gets added", systemImage: model.showHooks ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.quiet)
            if model.showHooks {
                ScrollView {
                    Text(model.detectedAgents
                            .map { "\(app.installer.configURL($0).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\n"
                                + app.installer.preview($0) }
                            .joined(separator: "\n\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 110)
                .padding(10)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
            }
        }
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
        return VStack(spacing: 12) {
            HStack(spacing: 18) {
                OnboardingBuddy(model: model, snapshot: model.heard == nil ? .onboarding(mood: "curious") : .onboarding(mood: "excited"),
                                size: 104)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.heard == nil ? "Open a new \(which) session and type anything" : "Heard you!")
                        .font(.boop(17, .bold)).foregroundStyle(Color(hex: Palette.inkDark))
                    Text(model.heard == nil ? "I'll wave when your agent's first hook reaches me."
                                            : "\(Agent(rawValue: model.heard ?? "")?.displayName ?? which) is connected. I'll be watching.")
                        .font(.system(size: 13)).foregroundStyle(Color(hex: Palette.inkSoftDark))
                    if model.heard != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: Palette.sageInkDark))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .terminalCard()
            .animation(.boopPop, value: model.heard)
            ForEach(Agent.allCases.filter { app.hookErrors[$0] != nil }, id: \.self) { agent in
                Text("Couldn't connect \(agent.displayName): \(app.hookErrors[agent] ?? "")")
                    .font(.system(size: 12)).foregroundStyle(Theme.clayInk)
            }
            Text("Sessions already open need a restart to pick up my hooks.")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var nav: some View {
        if model.connected {
            // Until an agent says hi, moving on is "later".
            ActNav(model: model, next: model.heard == nil ? "I'll try it later" : "Next")
        } else if model.detectedAgents.isEmpty || !app.installer.clientInPlace {
            ActNav(model: model)
        } else {
            ActNav(model: model, next: "Connect", enabled: !app.setup.agents.isEmpty) { model.connectAgents() }
        }
    }
}

/// Act 7: opening at login, the microphone, and the brain's key, each one
/// card and each skippable.
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
            mic
            OnboardingBrainKey(app: app)
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
    }

    private var loginDetail: String {
        if let why = app.loginItemError { return "Couldn't change it: \(why)" }
        return switch app.loginItemState {
        case .on, .off: "I only watch your agents while I'm open."
        case .needsApproval: "Allow me in System Settings, under General, Login Items."
        case .unavailable: "Only Boop.app opens at login."
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
        default: "macOS will ask for the microphone and speech. What you say stays on this Mac; only the words reach my brain."
        }
    }
}

/// Act 8: a celebration, on screen and on the board, the four things worth
/// remembering, and off to the menu bar. Without a board, the Mac's way
/// of each, and that the board is found once it's plugged in.
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
                    tip("hand.tap", "Tap my screen", "to poke me")
                    tip("mic", "Hold my button", "and talk")
                    tip("bell", "Amber? Tap me", "to open who's waiting", amber: true)
                } else {
                    tip("powerplug", "Got my body?", "plug it in, and I'll find it")
                    tip("mic", "Click Talk", "in my menu, then speak")
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
