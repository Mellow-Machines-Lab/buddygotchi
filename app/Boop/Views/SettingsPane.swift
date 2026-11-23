import AgentHooks
import BoopKit
import SwiftUI

/// Settings, inside the popover, in the order of use: the buddy itself
/// (its name, how much it says, its sound), the agents, the world, the
/// memory and the app. What only support needs (the body and its board,
/// the firmware, the simulator, the brain's key, uninstalling) waits under
/// Advanced, closed. When the body has trouble, one strip at the top says
/// so with its one fix, and the rows say only the short state.
struct SettingsPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat
    @ViewState private var apiKey = ""
    /// The key the Keychain holds, as far as this pane knows: nil until
    /// it's read.
    @ViewState private var savedKey: String?
    /// Typed in before the Keychain answered, which mustn't overwrite it.
    @ViewState private var keyEdited = false
    @ViewState private var keyFailed = false
    /// "Forget about me" was pressed once: it asks before it forgets.
    @ViewState private var confirmingForget = false
    @FocusState private var keyFocused: Bool
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Settings") { model.pane = .overview }
            FittedScroll(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    if model.device.trouble != nil { troubleStrip(model.device) }
                    PaneSection(model.name) { buddy }
                    PaneSection("Agents") { agents }
                    if let world = model.status?.world {
                        PaneSection("The world") { worldSetting(world) }
                    }
                    PaneSection("Memory") { memorySetting }
                    PaneSection("App") { app }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gutter)
            }
        }
        .task {
            // Off the main thread: a Keychain prompt would freeze the popover.
            let read = model.readKey
            let key = await Task.detached { read() }.value ?? ""
            if !keyEdited { apiKey = key }
            savedKey = key
        }
    }

    // MARK: Trouble

    /// The body's trouble, at full width, with its one fix: the rows below
    /// say only the short state.
    private func troubleStrip(_ device: AppModel.DeviceState) -> some View {
        Card(tone: Theme.clayInk) {
            HStack(alignment: .top, spacing: Theme.gapSnug) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.detail)
                    .foregroundStyle(Theme.clayInk)
                    .frame(width: Theme.iconColumn, height: SettingLine.firstLine)
                VStack(alignment: .leading, spacing: Theme.gapTight) {
                    Text(device.trouble ?? "").font(.bodyStrong).foregroundStyle(Theme.clayInk)
                        .frame(minHeight: SettingLine.firstLine)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(device.detail).font(.detail).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let more = device.more { MoreDetails(more) }
                    troubleFix(device.fix)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func troubleFix(_ fix: AppModel.DeviceState.Fix?) -> some View {
        switch fix {
        case .system(let label, let url)?:
            Button(label) { NSWorkspace.shared.open(url) }.buttonStyle(.row).padding(.top, Theme.gapTight)
        case .update?:
            // The write's progress is the firmware row's, under Advanced.
            Button("Update its firmware") {
                model.advancedOpen = true
                model.updateFirmware()
            }
            .buttonStyle(.row).padding(.top, Theme.gapTight)
            .disabled(model.firmwareWrite != .idle)
        case .showSimulator?:
            Button("Show it") { model.showSimulator() }.buttonStyle(.row).padding(.top, Theme.gapTight)
        case nil:
            EmptyView()
        }
    }

    // MARK: The buddy

    /// Its name, how much it says, whether it swears, how loud, and the
    /// work's words. Not running, none of it can change: one note says so.
    @ViewBuilder private var buddy: some View {
        if model.status == nil {
            NoteCard("\(model.name) isn't running, so its name, talk and sound can't change now.")
        } else {
            Card(padding: Card<EmptyView>.rows) {
                VStack(spacing: 0) {
                    nameRow
                    RowDivider()
                    talkRow
                    RowDivider()
                    SettingRow(icon: "exclamationmark.bubble", title: "Swearing",
                               detail: "\(model.name) may swear when things break.") {
                        Toggle("Swearing", isOn: Binding(get: { model.status?.swearing ?? false }, set: { model.setSwearing($0) }))
                            .toggleStyle(.boop).labelsHidden()
                    }
                    RowDivider()
                    colorRow
                    RowDivider()
                    SettingRow(icon: "sparkles", title: "Your agent helps \(model.name) think",
                               detail: "As \(model.name) sleeps, Claude Code or Codex writes what it remembers of you, on your own plan.") {
                        Toggle("Your agent helps", isOn: Binding(get: { model.status?.agentsThink ?? true }, set: { model.setAgentsThink($0) }))
                            .toggleStyle(.boop).labelsHidden()
                    }
                    RowDivider()
                    volumeRow
                    RowDivider()
                    SettingRow(icon: "keyboard", title: "Notices what you do at the Mac",
                               detail: "\(model.name) types and reads along, sways to your music and keeps still on a call. "
                                   + "It goes by timing and what's on, never what you type, read or copy.") {
                        Toggle("Notices what you do at the Mac",
                               isOn: Binding(get: { model.status?.noticesYou ?? true }, set: { model.setNoticesYou($0) }))
                            .toggleStyle(.boop).labelsHidden()
                    }
                    RowDivider()
                    placeRow
                }
            }
        }
    }

    /// Where the name is seen: by other buddies in the world, under the
    /// name the world took, and in which region.
    private var nameSeen: String {
        let name = model.name
        guard let world = model.status?.world else { return "\(name)'s name, here and on its board." }
        guard world.on else { return "Nobody else sees “\(name)” while \(name) is private." }
        if world.link.nameHidden { return "The world didn't take “\(name)”, so other buddies see “a buddy”." }
        let shown = world.link.shownName ?? name
        let region = World.Region(offset: world.utcOffset)?.name
        return "Other buddies see “\(shown)”" + (region.map { ", in \($0)." } ?? ".")
    }

    @ViewBuilder private var nameRow: some View {
        if let draft = model.renameDraft {
            SettingRow(icon: "character.cursor.ibeam", title: "Name",
                       detail: model.renameError ?? BuddyName.issue(draft) ?? "Once a week. Other buddies see the new name too.",
                       detailTone: model.renameError ?? BuddyName.issue(draft) == nil ? Theme.inkSoft : Theme.clayInk) {
                EmptyView()
            } below: {
                HStack(spacing: Theme.gapSnug) {
                    TextField("Name", text: Binding(get: { draft }, set: {
                        model.renameDraft = BuddyName.edited($0)
                        model.renameError = nil
                    }))
                    .font(.body)
                    .padding(.horizontal, Theme.gapSnug)
                    .frame(height: Theme.target)
                    .fieldBox(Theme.paper, radius: Theme.wellRadius, focus: $nameFocused)
                    .onSubmit { saveName() }
                    Button("Save", action: saveName).buttonStyle(.row)
                        .disabled(!BuddyName.valid(draft) || BuddyName.trimmed(draft) == model.name)
                    Button("Cancel") {
                        model.renameDraft = nil
                        model.renameError = nil
                    }
                    .buttonStyle(.quiet).font(.detailStrong)
                }
            }
        } else {
            SettingRow(icon: "character.cursor.ibeam", title: "Name", detail: nameSeen) {
                if let next = model.status?.nextRename {
                    // Once a week: the button says when.
                    Button("Rename on \(next.formatted(.dateTime.day().month(.abbreviated)))") {}
                        .buttonStyle(.row).disabled(true)
                        .help("\(model.name) can have a new name once a week.")
                } else {
                    Button("Rename…") {
                        model.renameDraft = model.name
                        model.renameError = nil
                        nameFocused = true
                    }
                    .buttonStyle(.row)
                    .help("Give \(model.name) a new name, here, on its board and in the world")
                }
            }
        }
    }

    private func saveName() {
        guard let draft = model.renameDraft, BuddyName.valid(draft) else { return }
        guard BuddyName.trimmed(draft) != model.name else { return model.renameDraft = nil }
        model.rename(draft) { why in
            model.renameError = why
            if why == nil { model.renameDraft = nil }
        }
    }

    private var talkRow: some View {
        // The chosen kind's line runs the row's width, under the control.
        SettingRow(icon: "bubble.left", title: "Talk", detail: model.talk.about(model.name), wide: true) {
            Segmented(label: "Talk", options: Talk.allCases.map { ($0, $0.title) },
                      chosen: Binding(get: { model.talk }, set: { model.setTalk($0) }))
        }
    }

    /// Where Boop sits beside your screen (`Anchor`): it follows your
    /// pointer from there, and turns to your Mac when an agent needs you.
    /// Not known until you show it.
    private var placeRow: some View {
        let status = model.status, name = model.name
        let gone = status?.anchorGone == true
        let detail = status?.placing == true
            ? "Move your pointer to the spot on your screen nearest \(name), then tap \(name)."
            : gone ? "Your screens changed. Show \(name) where it sits again, and it follows your pointer."
            : "\(name) follows your pointer, and turns to your screen when an agent needs you."
        let title = gone ? "Show \(name) where it sits again" : "Show \(name) where it sits"
        return SettingRow(icon: "cursorarrow.rays", title: title, detail: detail, wide: true) {
            Button(status?.placing == true ? "Cancel" : status?.anchored == true && !gone ? "Again" : "Show") { model.showWhereBoopSits() }
                .buttonStyle(.row)
                .disabled(status?.noticesYou == false)
        }
    }


    /// Eight swatches: the buddy's colour, on the board and in the world.
    private var colorRow: some View {
        let now = model.status?.snapshot.color ?? 0
        return SettingRow(icon: "paintpalette", title: "Colour",
                          detail: "\(model.name) is \(BuddyColor.of(now).name.lowercased()). Others in the world see it too.") {
            EmptyView()
        } below: {
            HStack(spacing: Theme.gapSnug) {
                ForEach(BuddyColor.all) { c in
                    Button { model.setColor(c.id) } label: {
                        Circle().fill(Color(hex: c.hex)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: c.id == now ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name)
                    .accessibilityAddTraits(c.id == now ? .isSelected : [])
                }
            }
            .padding(.vertical, Theme.gapTight)
        }
    }

    private var volumeRow: some View {
        let vol = model.status?.snapshot.vol ?? 6
        return SettingRow(icon: vol == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Volume") {
            HStack(spacing: Theme.gapSnug) {
                StepSlider(value: Binding(get: { vol }, set: { model.setVolume($0) }), most: 10)
                    .frame(width: 120)
                    .accessibilityLabel("Volume")
                Text(vol == 0 ? "Off" : "\(vol)")
                    .font(.detailStrong.monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: Theme.target, alignment: .trailing)
            }
        }
    }

    // MARK: Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Card(padding: Card<EmptyView>.rows) {
                VStack(spacing: 0) {
                    ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                        if index > 0 { RowDivider() }
                        agentRow(agent)
                    }
                }
            }
            if model.restartAgents {
                Label("Restart open agent sessions to pick up the change.", systemImage: "arrow.clockwise")
                    .caption()
                    .padding(.leading, Theme.gap)
            }
        }
    }

    /// No agent is connected: then Connect is the one thing to do, and
    /// filled.
    private var noneConnected: Bool {
        !Agent.allCases.contains { model.hooks[$0] == .installed }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let health = model.hooks[agent]
        let found = model.installer.detected(agent)
        // A short state; the why behind Details.
        let (text, tone, more): (String, Color, String?) = if let why = model.hookErrors[agent] {
            ("Couldn't change its hooks", Theme.clayInk, why)
        } else if !found {
            // Nothing to connect, so nothing missing for it.
            ("Not found on this Mac", Theme.inkSoft, nil)
        } else {
            switch health {
            case .installed?: ("Connected", Theme.sageInk, nil)
            case .outdated?: ("Needs a repair", Theme.clayInk, nil)
            case .unreadable(let why)?: ("Can't read its settings", Theme.clayInk, why)
            case .clientMissing?: ("Its hook helper is missing", Theme.clayInk, AppModel.clientMissing)
            case .hooksOff?: ("Its hooks are off in its own settings. Turn them on there.", Theme.clayInk, nil)
            default: ("Not connected", Theme.inkSoft, nil)
            }
        }
        return SettingRow(icon: agentSymbol(agent.rawValue), title: agent.displayName,
                          detail: text, detailTone: tone, more: more) {
            switch health {
            case .installed?:
                Button("Remove") { model.remove(agent) }.buttonStyle(.row)
            case .hooksOff(let file)?:
                // Boop never turns an agent's hooks back on: the person turned them off.
                Button("Show file") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
                    .buttonStyle(.row)
                    .help((file as NSString).abbreviatingWithTildeInPath)
            case .outdated?:
                Button("Repair") { model.install(agent) }.buttonStyle(.rowFilled)
            case .unreadable?, .clientMissing?:
                EmptyView()
            default:
                // Not on this Mac: nothing to do. Opening the popover looks
                // again, so Connect appears once it's installed.
                if found {
                    Button("Connect") { model.install(agent) }.buttonStyle(RowButtonStyle(filled: noneConnected))
                }
            }
        }
    }

    // MARK: World

    /// The switch, and under the card what the world gets. Off, Boop leaves
    /// the world: it's deleted there, and you can still look. Its name in
    /// the world is the Name row's.
    private func worldSetting(_ world: Runtime.WorldStatus) -> some View {
        let name = model.name
        return VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Card(padding: Card<EmptyView>.rows) {
                SettingRow(icon: "globe.europe.africa.fill", title: "Lives in the world",
                           detail: world.on ? "Other buddies can see \(name) and say hi."
                                            : "\(name) is private. You can still look around.") {
                    Toggle("Lives in the world", isOn: Binding(get: { world.on }, set: { model.runtime?.setWorld($0) }))
                        .toggleStyle(.boop).labelsHidden()
                }
            }
            Text("Shares its name, level, colour, days in a row, time zone, what it's doing, today's counts and its XP in the weekly league. Nothing you write.")
                .caption()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gap)
        }
    }

    // MARK: Memory

    /// What Boop remembers, a way to read it, and forgetting it, which asks
    /// first and never looks like the rows' buttons.
    private var memorySetting: some View {
        Card(padding: Card<EmptyView>.rows) {
            VStack(alignment: .leading, spacing: 0) {
                SettingRow(icon: "brain", title: "What \(model.name) remembers",
                           detail: "Written on this Mac as \(model.name) dreams. Its notes go to the brain with each request.") {
                    Button("See it ›") { model.pane = .memory }.buttonStyle(.row)
                }
                // Not running, nothing can forget.
                if model.status != nil {
                    RowDivider()
                    // Under the words, at their edge.
                    HStack(alignment: .top, spacing: Theme.gapSnug) {
                        Color.clear.frame(width: Theme.iconColumn, height: Theme.hair)
                        forgetLine.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.gap)
                    .padding(.vertical, Theme.gapTight)
                }
            }
        }
        .disabled(model.status == nil)
    }

    @ViewBuilder private var forgetLine: some View {
        if confirmingForget {
            VStack(alignment: .leading, spacing: 0) {
                Text("Forget the notes about you and your work, and your recent days? This can't be undone.")
                    .font(.detail).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.gapTight)
                HStack(spacing: Theme.gutter) {
                    Button("Forget") {
                        model.runtime?.forgetAboutYou()
                        confirmingForget = false
                    }
                    .buttonStyle(.wordLink(Theme.clayInk))
                    Button("Keep it") { confirmingForget = false }.buttonStyle(.wordLink(Theme.inkSoft))
                }
            }
        } else {
            Button("Forget about me…") { confirmingForget = true }
                .buttonStyle(.wordLink(Theme.clayInk))
                .help("Forget the notes about you and your work, and your recent days")
        }
    }

    // MARK: App

    private var app: some View {
        Card(padding: Card<EmptyView>.rows) {
            VStack(spacing: 0) {
                loginRow
                RowDivider()
                SettingRow(icon: "ladybug", title: "Bug report",
                           detail: "Shown in Finder, its path copied, for an agent or an issue.") {
                    Button("Save…") { model.saveReport() }.buttonStyle(.row)
                        .help("Save a bug report, to hand to an agent or attach to an issue")
                }
                .disabled(model.status == nil)
                // With no key, the brain's key can't wait under Advanced:
                // the Overview's notice sends you here for it.
                if model.noKey {
                    RowDivider()
                    key
                }
                RowDivider()
                advancedToggle
                if model.advancedOpen { advanced }
            }
        }
    }

    private var advancedToggle: some View {
        Button {
            withAnimation(.boopSettle) { model.advancedOpen.toggle() }
        } label: {
            HStack(alignment: .top, spacing: Theme.gapSnug) {
                Image(systemName: "chevron.right")
                    .font(.detailStrong)
                    .rotationEffect(.degrees(model.advancedOpen ? 90 : 0))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: Theme.iconColumn, height: SettingLine.firstLine)
                VStack(alignment: .leading, spacing: Theme.hair) {
                    Text("Advanced").font(.bodyMedium).foregroundStyle(Theme.ink)
                        .frame(minHeight: SettingLine.firstLine)
                    if !model.advancedOpen {
                        Text("The body and its board, updates, the brain's key, uninstall").caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advanced")
        .accessibilityValue(model.advancedOpen ? "open" : "closed")
    }

    @ViewBuilder private var advanced: some View {
        let device = model.device
        RowDivider()
        SettingRow(icon: "rectangle.inset.filled", title: "Body",
                   // With trouble, the strip at the top says it in full.
                   detail: device.trouble != nil ? device.short : device.detail,
                   detailTone: device.trouble != nil ? Theme.clayInk : device.connected ? Theme.sageInk : Theme.inkSoft,
                   more: device.trouble != nil ? nil : device.more) {
            // Reconnecting can't help while Boop isn't running or Bluetooth is off.
            if model.link != .none, let status = model.status, status.linkTrouble == nil {
                Button("Reconnect") { model.runtime?.reconnectDevice() }.buttonStyle(.row)
                    .help("Drop the connection and look for \(model.name)'s body again now")
            }
        }
        // The one board Boop takes over Bluetooth, once it has met one.
        if model.link == .bluetooth, let board = model.status?.board {
            RowDivider()
            SettingRow(icon: "pin.fill", title: "Paired board",
                       detail: "\(BoopDevice.advertised(board) ?? board). \(model.name) talks only to this board over Bluetooth.") {
                Button("Unpair") { model.runtime?.forgetBoard() }.buttonStyle(.row)
                    .help("Let \(model.name) take any board, and remember the next one tapped")
            }
        }
        // Newer firmware for the board, which the app writes over USB.
        if model.firmwareOffer != nil || model.firmwareWrite != .idle {
            RowDivider()
            firmwareRow
        }
        // The simulator's window is a body to choose, on or off, in the
        // builds that have it.
        if AppModel.offersSimulator {
            RowDivider()
            SettingRow(icon: "macwindow", title: "Simulator", detail: simulatorDetail) {
                HStack(spacing: Theme.gapSnug) {
                    if model.usingSimulator {
                        Button("Show") { model.showSimulator() }.buttonStyle(.row)
                            .help("Bring \(model.name)'s simulator window to the front")
                    }
                    Toggle("Simulator", isOn: Binding(get: { model.usingSimulator }, set: { model.use($0 ? .simulator : .board) }))
                        .toggleStyle(.boop).labelsHidden()
                        .help(model.usingSimulator ? "Go back to \(model.name)'s board" : "Make the simulator window \(model.name)'s body, from now on")
                }
            }
        }
        if !model.noKey {
            RowDivider()
            key
        }
        RowDivider()
        // Only the everyday Boop uninstalls; a copy on another folder says
        // so rather than ask and then do nothing.
        SettingRow(icon: "trash", title: "Uninstall",
                   detail: model.ownsHooks ? "Takes \(model.name) out of your agents and off this Mac. Its memory stays."
                                           : "Only the everyday Boop uninstalls. This copy runs on a folder of its own.") {
            Button("Uninstall…") { model.uninstall() }.buttonStyle(.row).disabled(!model.ownsHooks)
        }
    }

    /// What the simulator's row says: whether it's in use.
    private var simulatorDetail: String {
        model.usingSimulator ? "\(model.name)'s body is the simulator window, not its board."
            : "The simulator window, a board for when the board isn't here."
    }

    private var firmwareRow: some View {
        let version = model.firmwareOffer?.version ?? ""
        let runs = model.status?.device.map { "\(model.name)'s body runs \($0.fw). " } ?? ""
        let (text, tone): (String, Color) = switch model.firmwareWrite {
        case .idle: (runs + "Plug it into this Mac with a USB cable, then update. It takes about half a minute.", Theme.inkSoft)
        case .writing(let done): ("Writing… \(Int(done * 100))%. Keep the cable in.", Theme.inkSoft)
        case .done(let v): ("Updated to \(v). \(model.name)'s body is starting it.", Theme.sageInk)
        case .failed(let why): ("Couldn't update: \(why)", Theme.clayInk)
        }
        return SettingRow(icon: "arrow.down.circle", title: version.isEmpty ? "Firmware" : "Update to \(version)",
                          detail: text, detailTone: tone) {
            // Outlined: an update is offered, not broken.
            switch model.firmwareWrite {
            case .idle: Button("Update") { model.updateFirmware() }.buttonStyle(.row)
            case .failed: Button("Try again") { model.updateFirmware() }.buttonStyle(.row)
            case .writing, .done: EmptyView()
            }
        }
    }

    private var loginRow: some View {
        let state = model.loginItemState
        let (text, tone): (String, Color) = if let why = model.loginItemError {
            ("Couldn't change it: \(why)", Theme.clayInk)
        } else {
            switch state {
            case .on: ("\(model.name) opens when you log in, so it's there for your agents.", Theme.inkSoft)
            case .off: ("\(model.name) only watches your agents while it's open.", Theme.inkSoft)
            case .needsApproval: ("Allow \(model.name) in System Settings, under General, Login Items.", Theme.clayInk)
            case .unavailable: ("Only Boop.app opens at login, and this copy isn't it. Turn this on in Boop.app.", Theme.inkSoft)
            }
        }
        return SettingRow(icon: "power", title: "Open at login", detail: text, detailTone: tone) {
            if state == .needsApproval {
                Button("Open") { NSWorkspace.shared.open(LoginItem.settingsURL) }.buttonStyle(.row)
            } else {
                Toggle("Open at login", isOn: Binding(get: { state == .on }, set: { model.setOpenAtLogin($0) }))
                    .toggleStyle(.boop).labelsHidden()
                    .disabled(state == .unavailable)
            }
        }
    }

    // MARK: The brain's key

    /// What Boop does without a brain, if it has none:
    /// the rules' looks and reactions, but no brain reaction or mood change.
    private var brainNote: String? {
        guard model.noKey else { return nil }
        return "Without a Jev API key, \(model.name) shows what the agents are doing and when one needs you, but doesn't react or change its mood, and shrugs when you talk to it."
    }

    /// The field holds the key the Keychain has.
    private var keySaved: Bool {
        guard let savedKey, !savedKey.isEmpty else { return false }
        return Keychain.cleaned(apiKey) == savedKey
    }

    /// Something to save: a new key, or a blank field over a saved one.
    private var canSaveKey: Bool {
        guard let savedKey else { return false }
        let key = Keychain.cleaned(apiKey)
        return key != savedKey && !(key.isEmpty && savedKey.isEmpty)
    }

    private func saveKey() {
        let key = Keychain.cleaned(apiKey)
        Task {
            if await model.saveKey(key) {
                savedKey = key
                apiKey = key
                keyFailed = false
            } else {
                keyFailed = true
            }
        }
    }

    /// Jev's key, the brain's: a row like the others, the field under its
    /// words.
    private var key: some View {
        SettingRow(icon: "key", title: "Jev API key",
                   detail: keyFailed ? "Couldn't save the key in your Keychain. Try again, or check Keychain Access."
                       : "This is how \(model.name) thinks. It stays in your Keychain. What \(model.name) notices goes to TypeSafe, never your code.",
                   detailTone: keyFailed ? Theme.clayInk : Theme.inkSoft) {
            EmptyView()
        } below: {
            HStack(spacing: Theme.gapSnug) {
                SecureField("Jev API key", text: $apiKey)
                    .font(.body)
                    .padding(.horizontal, Theme.gapSnug)
                    .frame(height: Theme.target)
                    .fieldBox(Theme.paper, radius: Theme.wellRadius, focus: $keyFocused)
                    .onChange(of: apiKey) {
                        keyEdited = true
                        keyFailed = false
                    }
                    .onSubmit { if canSaveKey { saveKey() } }
                if keySaved {
                    // Done, not disabled.
                    Label("Saved", systemImage: "checkmark")
                        .font(.detailStrong)
                        .foregroundStyle(Theme.sageInk)
                        .frame(height: Theme.target)
                        .transition(.opacity)
                } else {
                    // A blank field takes the key out, and says so.
                    Button(Keychain.cleaned(apiKey).isEmpty && savedKey?.isEmpty == false ? "Remove" : "Save", action: saveKey)
                        .buttonStyle(.row)
                        .disabled(!canSaveKey)
                }
            }
            if let note = brainNote {
                Text(note).font(.detail).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A choice of a few short words, as the tab bar draws one: segments on a
/// well, the chosen one lifted. Drawn here rather than the system's
/// segmented control, which draws grey in the popover's inactive window.
struct Segmented<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var chosen: Value

    var body: some View {
        HStack(spacing: Theme.hair) {
            ForEach(options, id: \.value) { option in
                let on = option.value == chosen
                Button { withAnimation(.boopSettle) { chosen = option.value } } label: {
                    Text(option.title)
                        .font(on ? .bodyStrong : .bodyMedium)
                        .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                        .fixedSize()
                        .padding(.horizontal, Theme.gapSnug).padding(.vertical, Theme.hair)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: Theme.chipRadius).fill(Theme.lifted)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.hairline, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Theme.hair)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// What every settings line shares, whatever it holds.
enum SettingLine {
    /// The height of a title's first line, which its icon and control
    /// centre on.
    static let firstLine = Theme.gutter
}

/// One settings row: an icon, a title with a line under it, and a control
/// at the trailing edge, the icon and the control on the title's first
/// line however long the words run; and under the words, at their edge,
/// anything more (a field).
struct SettingRow<Trailing: View, Below: View>: View {
    let icon: String
    let title: String
    var detail: String?
    var detailTone: Color = Theme.inkSoft
    /// The raw detail under the plain words, behind Details.
    var more: String?
    /// The words under the title run under the control too, for a wide
    /// control beside a short title.
    var wide = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var below: Below

    init(icon: String, title: String, detail: String? = nil, detailTone: Color = Theme.inkSoft, more: String? = nil,
         wide: Bool = false, @ViewBuilder trailing: () -> Trailing, @ViewBuilder below: () -> Below) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.detailTone = detailTone
        self.more = more
        self.wide = wide
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.gapSnug) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
                .frame(width: Theme.iconColumn, height: SettingLine.firstLine)
            VStack(alignment: .leading, spacing: Theme.hair) {
                HStack(alignment: .top, spacing: Theme.gapSnug) {
                    Text(title).font(.bodyMedium)
                        .frame(minHeight: SettingLine.firstLine)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if wide { control }
                }
                if let detail {
                    Text(detail).font(.detail).foregroundStyle(detailTone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let more { MoreDetails(more) }
                if Below.self != EmptyView.self {
                    VStack(alignment: .leading, spacing: Theme.gapTight) { below }
                        .padding(.top, Theme.gapTight)
                }
            }
            // The words take the room the control leaves, so they wrap only
            // when they must.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Centred on the first line: a taller control reaches into the
            // row's padding and never pushes the words down.
            if !wide { control }
        }
        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
    }

    private var control: some View {
        trailing.fixedSize()
            .frame(height: SettingLine.firstLine)
    }
}

extension SettingRow where Below == EmptyView {
    init(icon: String, title: String, detail: String? = nil, detailTone: Color = Theme.inkSoft, more: String? = nil,
         wide: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(icon: icon, title: title, detail: detail, detailTone: detailTone, more: more, wide: wide, trailing: trailing,
                  below: { EmptyView() })
    }
}
