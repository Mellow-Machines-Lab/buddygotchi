import AgentHooks
import BoopKit
import SwiftUI

/// Settings, inside the popover: sound, agents and hooks, the
/// device, and the personality with Jev's key.
struct SettingsPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat
    @ViewState private var apiKey = ""
    @ViewState private var keySaved = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title row: a Back chevron and the title.
            HStack(spacing: Theme.gapTight) {
                Button { model.pane = .overview } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.quiet)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
                Text("Settings").font(.boop(16))
                Spacer()
            }
            .padding(.horizontal, Theme.gutter - 8)
            .padding(.top, Theme.gutter - 4)
            .padding(.bottom, Theme.gap)
            FittedScroll(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    PaneSection("Sound") { sound }
                    PaneSection("Agents") { agents }
                    PaneSection("Device") { device }
                    PaneSection("Personality") { personality }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gapLoose)
            }
        }
        .task {
            // Off the main thread: a Keychain prompt would freeze the popover.
            let read = model.readKey
            apiKey = await Task.detached { read() }.value ?? ""
        }
    }

    // MARK: Sound

    private var sound: some View {
        let s = model.status?.snapshot
        return Card(padding: 0) {
            SettingRow(icon: s?.vol == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Volume",
                       detail: "How loud \(model.name) talks.") {
                HStack(spacing: 6) {
                    Slider(value: Binding(get: { Double(s?.vol ?? 6) },
                                          set: { model.setVolume(Int($0.rounded())) }),
                           in: 0...10, step: 1)
                        .controlSize(.small)
                        .frame(width: 84)
                        .accessibilityLabel("Volume")
                    Text(s.map { $0.vol == 0 ? "Off" : "\($0.vol)" } ?? "–")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .disabled(model.status == nil)
    }

    // MARK: Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                        if index > 0 { Hairline().padding(.leading, 40).padding(.trailing, 12) }
                        agentRow(agent)
                    }
                }
            }
            if model.restartAgents {
                Label("Restart open agent sessions to pick up the change.", systemImage: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .padding(.leading, 2)
            }
        }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let health = model.hooks[agent]
        let found = model.installer.detected(agent)
        let (text, tone): (String, Color) = if let why = model.hookErrors[agent] {
            ("Couldn't change its hooks: \(why)", Theme.clayInk)
        } else if !found {
            // Nothing to connect, so nothing missing for it.
            ("Not found on this Mac", Theme.inkSoft)
        } else {
            switch health {
            case .installed?: ("Connected", Theme.sageInk)
            case .outdated?: ("Needs a repair", Theme.clayInk)
            case .unreadable(let why)?: ("Can't read its settings: \(why)", Theme.clayInk)
            case .clientMissing?: ("agent-hook isn't built. Run make build, then restart Boop.", Theme.clayInk)
            case .hooksOff(let file)?: ("Its hooks are turned off in \((file as NSString).abbreviatingWithTildeInPath)", Theme.clayInk)
            default: ("Not connected", Theme.inkSoft)
            }
        }
        return SettingRow(icon: agentSymbol(agent.rawValue), title: agent.displayName,
                          detail: text, detailTone: tone) {
            switch health {
            case .installed?, .hooksOff?:
                Button("Remove") { model.remove(agent) }.buttonStyle(.row)
            case .outdated?:
                Button("Repair") { model.install(agent) }.buttonStyle(.rowFilled)
            case .unreadable?, .clientMissing?:
                EmptyView()
            default:
                // Not on this Mac: nothing to do. Opening the popover looks
                // again, so Connect appears once it's installed.
                if found { Button("Connect") { model.install(agent) }.buttonStyle(.rowFilled) }
            }
        }
    }

    // MARK: Device

    private var device: some View {
        let device = model.device
        return Card(padding: 0) {
            VStack(spacing: 0) {
                SettingRow(icon: "rectangle.inset.filled", title: "\(model.name)'s body", detail: device.detail,
                           detailTone: device.trouble ? Theme.clayInk : device.connected ? Theme.sageInk : Theme.inkSoft) {
                    // Reconnecting can't help while Boop isn't running or Bluetooth is off.
                    if model.link != .none, let status = model.status, status.linkTrouble == nil {
                        Button("Reconnect") { model.runtime?.reconnectDevice() }.buttonStyle(.row).fixedSize()
                            .help("Drop the connection and look for \(model.name)'s body again now")
                    }
                }
                // A simulator running on this Mac is a body to choose, while it runs.
                if model.simulatorThere || model.usingSimulator {
                    Hairline().padding(.leading, 40).padding(.trailing, 12)
                    SettingRow(icon: "macwindow", title: "Simulator",
                               detail: model.usingSimulator ? "\(model.name) is using the simulator in your browser, not its board."
                                   : "A simulated board is running on this Mac.") {
                        Button(model.usingSimulator ? "Use the board" : "Use it") {
                            model.use(model.usingSimulator ? .board : .simulator)
                        }.buttonStyle(.row).fixedSize()
                            .help(model.usingSimulator ? "Go back to \(model.name)'s board" : "Use the simulator as \(model.name)'s body until it stops")
                    }
                }
            }
        }
    }

    // MARK: Personality

    /// What each personality does, in one line: the
    /// character pack's (characters/CHARACTER.md §4).
    private func about(_ personality: Personality) -> String { personality.about ?? "" }

    /// What Boop does without a brain, if it has none:
    /// the rules' looks and one-shots, but no reaction or mood change.
    private var brainNote: String? {
        guard model.noKey else { return nil }
        return "Without a Jev API key, \(model.name) shows what the agents are doing and when one needs you, but doesn't react or change its mood."
    }

    private var personality: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    PersonalityPicker(personality: Binding(get: { model.personality }, set: { model.setPersonality($0) }))
                    Text(about(model.personality))
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = brainNote {
                        Text(note)
                            .font(.system(size: 11)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .disabled(model.status == nil)
                key
            }
        }
    }

    /// Jev's key, only where it's used.
    private var key: some View {
        VStack(spacing: 0) {
            Hairline().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.gapSnug) {
                    // As tall as the Save button beside it.
                    SecureField("Jev API key", text: $apiKey)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .fieldBox(Theme.paper, radius: 7, focus: $keyFocused)
                        .onChange(of: apiKey) { keySaved = false }
                    if keySaved {
                        // Done, not disabled.
                        Label("Saved", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.sageInk)
                            .frame(height: 22)
                            .transition(.opacity)
                    } else {
                        Button("Save") {
                            // Off the main thread: the Keychain may stop to ask.
                            let key = apiKey
                            Task {
                                keySaved = await Task.detached { Keychain.setJevKey(key) }.value
                                // The brain uses it from the next event.
                                if keySaved { model.runtime?.reloadBrain(jevKey: key.isEmpty ? nil : key) }
                            }
                        }
                        .buttonStyle(.row)
                    }
                }
                Text("Kept in your Keychain. With Jev, what happens and \(model.name)'s personality and mood go to TypeSafe with each call.")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .transition(.opacity)
    }
}

/// Boop or Chatter: equal segments on a well, the chosen one raised on
/// paper. Drawn here rather than the system's segmented control,
/// which doesn't stretch, and draws grey in the popover's inactive window.
struct PersonalityPicker: View {
    @Binding var personality: Personality
    @Namespace private var chosen

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Personality.allCases, id: \.self) { p in
                let on = p == personality
                Button {
                    withAnimation(.boopSettle) { personality = p }
                } label: {
                    Text(p.rawValue.capitalized)
                        .font(.system(size: 11, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.paper)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                                    .matchedGeometryEffect(id: "chosen", in: chosen)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personality")
    }
}

/// One settings row: an icon, a title with a line under it, and a control
/// at the trailing edge.
struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    var detailTone: Color = Theme.inkSoft
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.gapSnug + 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(detailTone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The words take the room the control leaves, so they wrap only
            // when they must.
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing.fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
