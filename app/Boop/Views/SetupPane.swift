import AgentHooks
import BoopKit
import SwiftUI

/// First launch, inside the popover: hello, a name and sweet or
/// cheeky, which agents to watch, then wake Boop up. One thing per step.
struct SetupPane: View {
    @ObservedObject var model: AppModel
    @ViewState private var forward = true
    @ViewState private var showHooks = false
    @FocusState private var nameFocused: Bool

    private var step: SetupDraft.Step { model.setup.step }
    private var name: String { model.setup.trimmedName.isEmpty ? "Boop" : model.setup.trimmedName }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, Theme.gutter)
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                        removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(height: 448)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, Theme.gutter)
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(SetupDraft.Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.ink : Theme.hairlineStrong)
                    .frame(width: s == step ? 26 : 12, height: 5)
            }
        }
        .animation(.boopEase(0.3), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SetupDraft.Step.allCases.count)")
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .hello: hello
        case .name: naming
        case .agents: agents
        case .ready: ready
        }
    }

    private func go(_ to: SetupDraft.Step) {
        forward = to.rawValue > step.rawValue
        withAnimation(.boopEase(0.35)) { model.setup.step = to }
    }

    private func title(_ text: String, _ detail: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(text).font(.boop(20)).multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // Narrower than the column, so lines break evenly
                    // instead of leaving one word on the last.
                    .frame(maxWidth: 290)
            }
        }
    }

    private func nav(back: SetupDraft.Step?, next: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack {
            if let back {
                // Its hover padding hangs outside, so the word lines up with the column.
                Button("Back") { go(back) }.buttonStyle(.quiet).font(.system(size: 12)).padding(.leading, -8)
            }
            Spacer()
            Button(next, action: action)
                .buttonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
        }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: Theme.gapLoose) {
            Spacer()
            BoopFace(mood: .idle, size: 104)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            title("Hi! I'm Boop.",
                  "A little creature for your desk. I watch your coding agents, react when they finish, and tell you when one needs you.")
            Spacer()
            Button("Let's go") { go(.name) }
                .buttonStyle(ProminentButtonStyle(wide: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var naming: some View {
        VStack(spacing: Theme.gap) {
            Spacer(minLength: 0)
            BoopFace(mood: model.setup.nature == .cheeky ? .cheeky : .happy, size: 88)
            title("What should I be called?")
            TextField("A name", text: Binding(
                get: { model.setup.name },
                set: { model.setup.editName($0) }))
                .font(.boop(16, .medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, 9)
                .fieldBox(Theme.raised, radius: 10, focus: $nameFocused)
                .onAppear { nameFocused = true }
            Text(model.setup.nameIssue ?? "Names are for keeps, so pick one you love.")
                .font(.system(size: 11)).foregroundStyle(model.setup.nameIssue == nil ? Theme.inkSoft : Theme.clayInk)
            Text("Sweet or cheeky?").font(.system(size: 12, weight: .semibold)).padding(.top, Theme.gapSnug)
            HStack(spacing: Theme.gapSnug) {
                natureCard(.sweet, "heart.fill", Theme.blush, "Sweet", "Warm and encouraging")
                natureCard(.cheeky, "face.smiling.inverse", Theme.inkSoft, "Cheeky", "Playful, a bit sassy")
            }
            Spacer(minLength: 0)
            nav(back: .hello, next: "Continue", enabled: model.setup.canContinueName) { go(.agents) }
        }
    }

    private func natureCard(_ nature: LongTerm.Nature, _ icon: String, _ tone: Color, _ title: String, _ detail: String) -> some View {
        let selected = model.setup.nature == nature
        return Button {
            withAnimation(.boopPop) { model.setup.nature = nature }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tone)
                    .scaleEffect(selected ? 1.12 : 1)
                Text(title).font(.boop(13))
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Theme.well : Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var agents: some View {
        let detected = Agent.allCases.filter(model.installer.detected)
        return VStack(spacing: Theme.gap) {
            title("Which agents should I watch?",
                  "I listen through their hooks. I never approve, deny or block anything.")
                .padding(.top, Theme.gapLoose)
            VStack(spacing: Theme.gapSnug) {
                ForEach(Agent.allCases, id: \.self) { agentRow($0) }
            }
            .padding(.top, Theme.gapTight)
            if !model.installer.clientInPlace {
                Text(AppModel.bundled ? "My hook helper is missing, so I can't add hooks yet. Install Boop again, then connect them in Settings."
                                      : "agent-hook isn't built, so I can't add hooks yet. Run make build, restart Boop, then connect them in Settings.")
                    .font(.system(size: 11)).foregroundStyle(Theme.clayInk).multilineTextAlignment(.center)
            } else if !detected.isEmpty {
                // A disclosure of our own: the system's chevron ignores the
                // tint and glares white on dark paper.
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.boopSettle) { showHooks.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showHooks ? 90 : 0))
                            Text("See exactly what gets added").font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.inkSoft)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showHooks ? "Shown" : "Hidden")
                    if showHooks {
                        ScrollView {
                            Text(detected.filter { model.setup.agents.contains($0) }.map { agent in
                                "\(model.installer.configURL(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\n"
                                    + model.installer.preview(agent)
                            }.joined(separator: "\n\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(height: 104)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            nav(back: .name, next: "Continue") { go(.ready) }
        }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let found = model.installer.detected(agent)
        let on = found && model.installer.clientInPlace && model.setup.agents.contains(agent)
        return Card(padding: 0) {
            SettingRow(icon: agentSymbol(agent.rawValue), title: agent.displayName,
                       detail: found ? "Found on this Mac" : "Not found. You can add it later in Settings.",
                       detailTone: found ? Theme.sageInk : Theme.inkSoft) {
                Toggle("Watch \(agent.displayName)", isOn: Binding(get: { on }, set: { value in
                    if value { model.setup.agents.insert(agent) } else { model.setup.agents.remove(agent) }
                }))
                .toggleStyle(.switch)
                // On is sage, like connected. The popover's ink tint would be
                // a near-white track under the white knob in dark.
                .tint(Theme.sage)
                .labelsHidden()
                .disabled(!found || !model.installer.clientInPlace)
            }
        }
        .opacity(found ? 1 : 0.75)
    }

    private var ready: some View {
        VStack(spacing: Theme.gapLoose) {
            Spacer(minLength: 0)
            BoopFace(mood: .happy, size: 88)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            title("Ready to wake \(name)?")
            VStack(alignment: .leading, spacing: Theme.gap) {
                tip("powerplug.fill", "Plug \(name)'s body into USB power. It finds this Mac over Bluetooth by itself.")
                tip("hand.raised.fill", "macOS will ask to use Bluetooth.")
                if !model.setup.agents.isEmpty && model.installer.clientInPlace {
                    tip("arrow.clockwise", "Restart any open agent sessions afterwards so I can hear them.")
                }
            }
            .padding(.horizontal, 4)
            if let error = model.setup.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.clayInk).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            nav(back: .agents, next: "Wake \(name) up") { model.finishSetup() }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug + 2) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.inkSoft).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
