import AgentHooks
import AppKit
import BoopKit
import SwiftUI

/// The overview: Boop at the top, the same on every tab, then its three
/// tabs. Now, in the order of need: who needs you, what's wrong, every
/// session sorted by need, how Boop feels and why, and what it celebrates
/// today. The Boop and World tabs are their own views. Controls live in
/// Settings; the exceptions are the mic button and Hush, in its menu.
struct OverviewPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TabBar(tab: $model.tab)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, Theme.gapSnug)
            FittedScroll(maxHeight: maxHeight - 76 - TabBar.height) {
                Group {
                    switch model.tab {
                    case .now: now
                    case .boop: BoopPane(model: model)
                    case .world: WorldPane(model: model)
                    }
                }
                .padding(.top, Theme.gap)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gutter)
            }
        }
        // The header grows when reminder chips appear. Bound the whole
        // pane too, so its scroll view gives that extra height back.
        .frame(maxHeight: maxHeight)
    }

    // MARK: Now

    private var now: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            // Someone waiting comes first, before anything else.
            if let attn = model.status?.snapshot.attn {
                needsYou(attn, model.status?.sessions ?? [])
            }
            let notices = notices
            if !notices.isEmpty {
                NoticeStrip(notices: notices, foldKey: NoticeStrip.foldKey(model))
            }
            if let status = model.status, let shown = status.show {
                PaneSection("Shown") { ShowCard(shown: shown) }
            }
            if let status = model.status {
                PaneSection(status.sessions.isEmpty ? "Your agents" : "Your agents · \(status.sessions.count)") {
                    sessions(status)
                }
                // In words, so a face never needs decoding; after the
                // sessions, since what needs you outranks how it feels.
                ReasonLines(feed: model.slime, name: model.name, mood: status.snapshot.mood, wish: status.wishing,
                            why: moodWhy, doing: status.doingReason?.cause,
                            energy: Narration.energy(status.snapshot.energy, name: model.name))
                if !status.dressing.isEmpty {
                    PaneSection("Why it looks like this") { dressingCard(status.dressing) }
                }
            } else if model.startError == nil {
                NoteCard("Waking up… Your agents show here in a moment.")
            }
        }
    }

    /// Every trouble worth a line, most urgent first: what the person can
    /// do about each, and whether it can go.
    private var notices: [PaneNotice] {
        var all: [PaneNotice] = []
        let trouble = "exclamationmark.triangle.fill"
        if let error = model.startError {
            all.append(PaneNotice(icon: trouble, tone: Theme.clayInk, title: "Boop couldn't start", detail: error,
                                  // The pane's only content: its words in place.
                                  action: ("Try again", model.start), inline: true))
        }
        if model.status?.uncleanExit == true {
            all.append(PaneNotice(icon: trouble, tone: Theme.clayInk, title: "\(model.name) stopped unexpectedly",
                                  detail: "It didn't close properly last time. A bug report keeps what it knew, with macOS's crash report if there is one.",
                                  action: ("Save a bug report", model.saveReport),
                                  dismiss: { model.runtime?.dismissUncleanExit() }))
        }
        let device = model.device
        if let title = device.trouble {
            let action: NoticeAction? = switch device.fix {
            case .system(let label, let url)?: (label, { NSWorkspace.shared.open(url) })
            case .update?: openSettings
            case .showSimulator?: ("Show it", { model.showSimulator() })
            case nil: nil
            }
            all.append(PaneNotice(icon: trouble, tone: Theme.clayInk, title: title, detail: device.detail,
                                  action: action, more: device.more))
        }
        if let trouble = model.status?.brainTrouble { all.append(brainNotice(trouble)) }
        if let why = model.status?.micTrouble {
            all.append(PaneNotice(icon: "mic.slash.fill", tone: Theme.clayInk, title: "\(model.name) can't hear you", detail: why,
                                  dismiss: { model.dismissMicTrouble() }))
        }
        if model.restartAgents {
            all.append(PaneNotice(icon: "arrow.clockwise", tone: Theme.inkSoft, title: "Restart your agent sessions",
                                  detail: "Open sessions pick up Boop's hooks when they restart.",
                                  dismiss: { model.restartAgents = false }))
        }
        // A change that failed, at setup or in Settings, until it's dismissed
        // or the hooks change.
        for agent in Agent.allCases where model.hookErrors[agent] != nil && !model.hookErrorsDismissed.contains(agent) {
            all.append(PaneNotice(icon: trouble, tone: Theme.clayInk, title: "Couldn't change \(agent.displayName)'s hooks",
                                  detail: "\(agent.displayName)'s settings were left as they were.", action: openSettings,
                                  more: model.hookErrors[agent], dismiss: { model.dismissHookError(agent) }))
        }
        return all
    }

    // MARK: Header

    /// Under the header, over the tabs.
    private static let headerGap: CGFloat = Theme.gapTight

    /// Two rows as tall as the face: the name and Talk, then one status
    /// line and the board's state. The status line is cut at its end
    /// rather than push anything, so the column never grows past the
    /// popover; the name wraps, and the controls and the board's state keep
    /// their own widths at the ends of the rows.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            HStack(alignment: .top, spacing: Theme.gap) {
                face
                VStack(alignment: .leading, spacing: Theme.gapTight) {
                    // The name on one line while it fits beside the controls;
                    // else it wraps, and while it's quiet for a while the controls shrink to
                    // their icons, so no word of the name breaks.
                    ViewThatFits(in: .horizontal) {
                        nameRow(wraps: false, compact: false)
                        nameRow(wraps: true, compact: model.status?.quietUntil != nil)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        statusLine
                        if model.status != nil { oneDevice }
                    }
                }
            }
            // Under the name, so the chips never squeeze each other or the
            // board's state.
            chips.padding(.leading, faceSize + Theme.gap)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Self.headerGap)
    }

    private let faceSize: CGFloat = 46

    private func nameRow(wraps: Bool, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.gapSnug) {
            Text(model.name).font(.boopTitle)
                .fixedSize(horizontal: !wraps, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.status != nil { talkControls(compact: compact) }
        }
        .frame(minHeight: Theme.target)
    }

    /// The pack's mirror of the board, or the still face; its edge amber
    /// while something needs you.
    @ViewBuilder private var face: some View {
        if showsSlime {
            SlimeFace(feed: model.slime, snapshot: model.status?.snapshot ?? Self.waking, live: model.shown, size: faceSize,
                      needsYou: FaceMood(model.status) == .needsYou)
        } else {
            BoopFace(mood: model.startError == nil ? FaceMood(model.status) : .stopped, design: model.status?.snapshot.mood ?? MoodOutput.initial,
                     size: faceSize)
        }
    }

    /// The pack's mirror of the board whenever it has one, connected or
    /// not, so the face never changes creature: unless the board connected
    /// runs another character, or Boop couldn't start, which the still
    /// face's crossed eyes say.
    private var showsSlime: Bool {
        guard SlimeFeed.folder != nil, model.startError == nil else { return false }
        return !(model.status?.connected == true && model.status?.device?.hasTheCharacter == false)
    }

    /// Why Boop feels as it does, after the line that names the mood.
    private var moodWhy: String? { model.status?.moodReason?.cause }

    /// The slime while the runtime starts, before its first status.
    private static let waking = StateSnapshot(doing: "asleep", mood: CharacterPack.active.startupMood, attn: nil, working: 0, vol: 0)

    /// How things are and how Boop feels, on one line: "2 need you ·
    /// feeling calm". The mood is in words, so it doesn't rest on telling
    /// the faces apart.
    private var statusLine: some View {
        let waiting = model.status?.snapshot.waiting ?? 0
        let headline = waiting > 1 && !model.listening ? "\(waiting) need you" : model.headline
        let mood = model.status?.snapshot.mood
        var line = Text(headline)
        if let mood { line = line + Text(" · feeling ") + Text(mood).fontWeight(.medium) }
        return HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
            StateDot(tone: tone, pulsing: live)
            line.font(.body).foregroundStyle(Theme.inkSoft)
                .lineLimit(1).truncationMode(.tail)  // cut: whole in .help
                .help(mood.map { "\(headline), feeling \($0)" } ?? headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.boopSettle, value: headline)
        .animation(.boopSettle, value: mood)
        .accessibilityElement(children: .combine)
    }

    /// Small reminders of what's set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is the usual.
    @ViewBuilder private var chips: some View {
        if let status = model.status {
            let all: [(String, String)?] = [
                status.talk != .default ? ("bubble.left.and.bubble.right.fill", status.talk.title) : nil,
                status.snapshot.vol == 0 ? ("speaker.slash.fill", "Muted") : nil,
            ]
            let chips = all.compactMap { $0 }
            if !chips.isEmpty {
                HStack(spacing: Theme.gapTight) {
                    ForEach(chips, id: \.1) { icon, text in Chip(text, icon: icon) }
                }
                .transition(.opacity)
            }
        }
    }

    /// Whether Boop's body is connected, as plain words, so it doesn't look
    /// like a button. Which board it is stays out of sight.
    private var oneDevice: some View {
        let device = model.device
        return HStack(spacing: Theme.gapTight) {
            Circle().fill(device.trouble != nil ? Theme.clayInk : device.connected ? Theme.sageSignal : Theme.inkFaint)
                .frame(width: 6, height: 6)
            Text(device.short)
                .font(.chip)
                .foregroundStyle(device.trouble != nil ? Theme.clayInk : Theme.inkSoft)
        }
        .fixedSize()
        .help(device.detail)
        .animation(.boopSettle, value: device.short)
    }

    /// Talk, and beside it while it's quiet for a while the one control
    /// that says so and ends it; else a small menu that hushes.
    private func talkControls(compact: Bool) -> some View {
        HStack(spacing: Theme.gapTight) {
            if let until = model.status?.quietUntil {
                quietButton(until, compact: compact)
            }
            talkButton(compact: compact)
            if model.status?.quietUntil == nil { talkMenu }
        }
        .fixedSize()
    }

    /// While it's quiet for a while, how long until Talk is the setting's
    /// again, counting down; a click ends it now.
    private func quietButton(_ until: Date, compact: Bool) -> some View {
        Button { model.runtime?.quietForAWhile(false) } label: {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let minutes = max(1, Int((until.timeIntervalSince(context.date) / 60).rounded(.up)))
                HStack(spacing: Theme.gapTight) {
                    Image(systemName: "mouth.fill")
                    Text(compact ? "\(minutes)m" : "Quiet \(minutes)m")
                }
            }
        }
        .buttonStyle(.rowFilled)
        .help("\(model.name) keeps quiet until the time's up. Click to let it talk now")
        .accessibilityLabel("Quiet for now. Let \(model.name) talk again")
        .transition(.opacity)
    }

    /// Talk's menu: Hush for half an hour (`Core.quietForMs`): Talk is
    /// quiet till then.
    private var talkMenu: some View {
        Menu {
            Button("Hush for \(Core.quietForMs / 60_000) min") { model.runtime?.quietForAWhile() }
        } label: {
            Image(systemName: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.chip)
        .foregroundStyle(Theme.inkSoft)
        .frame(width: Theme.iconColumn, height: Theme.target)
        .help("Hush \(model.name) for \(Core.quietForMs / 60_000) min: it keeps making faces, and says very little")
        .accessibilityLabel("More: hush \(model.name)")
    }

    /// Push-to-talk from the Mac: click to talk, click
    /// again to send. The device's BOOT button does the same while held.
    private func talkButton(compact: Bool) -> some View {
        let on = model.listening
        return Button(action: model.toggleTalk) {
            HStack(spacing: Theme.gapTight) {
                Image(systemName: on ? "arrow.up" : "mic.fill")
                // Both words in the same place, so the button doesn't jump.
                if !compact {
                    ZStack {
                        Text("Send").opacity(on ? 1 : 0)
                        Text("Talk").opacity(on ? 0 : 1)
                    }
                }
            }
        }
        .buttonStyle(RowButtonStyle(filled: on))
        .help(on ? "Stop listening and send what \(model.name) heard"
                 : "Talk to \(model.name) with the Mac's microphone: try “how many agents are running?” It stops by itself after 30 seconds")
        .accessibilityLabel(on ? "Stop listening and send" : "Talk to \(model.name)")
        .animation(.boopSettle, value: on)
    }

    private var tone: Color {
        if model.listening { return Theme.recording }
        return switch FaceMood(model.status) {
        case .needsYou: Theme.amberSignal
        case .working: Theme.inkSoft
        case .idle, .happy, .asleep, .stopped, .waking: Theme.inkFaint
        }
    }

    private var live: Bool {
        let mood = FaceMood(model.status)
        return model.listening || mood == .working || mood == .needsYou
    }

    // MARK: Why it looks like this

    /// What Boop is celebrating today, and the night: each reason, and what
    /// the board wears or shows for it.
    private func dressingCard(_ reasons: [Narration.Dressing]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                ForEach(reasons) { reason in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        Image(systemName: symbol(reason.kind)).font(.body).foregroundStyle(Theme.inkSoft)
                            .frame(width: Theme.iconColumn)
                        VStack(alignment: .leading, spacing: Theme.hair) {
                            Text(reason.why).font(.bodyStrong)
                            if let what = reason.what {
                                Text(what.prefix(1).uppercased() + what.dropFirst()).caption()
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ kind: Narration.Dressing.Kind) -> String {
        switch kind {
        case .specialDay: "party.popper"
        case .night: "moon.stars"
        }
    }

    // MARK: Needs you

    /// The card names the session that has waited longest, as the device
    /// does, but in full: the snapshot's project and thread name are cut to
    /// fit the device. Its name first, then where it runs, then what it
    /// asks of you, then two buttons: open it where it runs, as a tap on
    /// the board's needs-you screen does, or dismiss it from Boop.
    private func needsYou(_ attn: StateSnapshot.Attention, _ sessions: [SessionSummary]) -> some View {
        // The request the card names: never one dismissed, and the agent's
        // that asks.
        let waiting = sessions.first { $0.status == .waiting && !$0.dismissed && $0.agent == attn.agent }
            ?? sessions.first { $0.status == .waiting && !$0.dismissed }
        let (title, project) = rowTitle(project: waiting?.project ?? attn.project, name: waiting?.name ?? attn.name)
        let place = [project, waiting?.workspace].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let agent = Agent(rawValue: attn.agent)?.displayName ?? attn.agent
        let kind = waiting?.asks ?? attn.kind
        let ask = kind.map { "\(agent) is asking for \($0.words)." } ?? "\(agent) is waiting for you."
        let thread = waiting?.thread
        let opens = thread.flatMap(ThreadLink.target)
        return VStack(alignment: .leading, spacing: Theme.hair) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                Text(title).font(.bodyStrong)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if attn.more > 0 {
                    Text("1 of \(attn.more + 1)").font(.detail).foregroundStyle(Theme.amberInk).fixedSize()
                }
            }
            if !place.isEmpty {
                Text(place).caption().fixedSize(horizontal: false, vertical: true)
            }
            Text(ask).font(.body).foregroundStyle(Theme.amberInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.gapTight)
            if let thread {
                HStack(spacing: Theme.gapSnug) {
                    if let opens {
                        Button(openLabel(opens)) { model.runtime?.openThread(thread) }
                            .buttonStyle(.rowFilled)
                            .help(openVerb(opens).prefix(1).uppercased() + openVerb(opens).dropFirst())
                    }
                    // Hides the request on Boop, as a finger held on the
                    // needs-you screen does; the agent still waits. It names
                    // the request the card shows, so one that took its place
                    // since isn't dismissed unseen.
                    Button("Dismiss") { model.runtime?.dismiss(thread, request: attn.id) }
                        .buttonStyle(.row)
                        .help("Stop showing this on \(model.name). \(agent) still waits.")
                }
                .padding(.top, Theme.gapSnug)
            }
        }
        .padding(Theme.gap)
        .padding(.leading, Theme.gapTight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(Theme.needsYouTint), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        // A bar down its leading edge, so it outweighs the face and the tabs.
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.amberSignal).frame(width: Theme.gapTight)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.amberSignal.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        .animation(.boopPop, value: title)
    }

    // MARK: Sessions

    /// Sessions reach Boop only through the hooks, so with none connected
    /// the list can't promise any, and says where to connect them. Else one
    /// list in one card, sorted by need: needs you, working, idle.
    @ViewBuilder private func sessions(_ status: Runtime.Status) -> some View {
        let heard = Agent.allCases.filter { model.hooks[$0] == .installed || model.hooks[$0] == .outdated }
        if status.sessions.isEmpty, heard.isEmpty {
            NoticeStrip(notices: [PaneNotice(icon: "ear", tone: Theme.inkSoft, title: "\(status.name) isn't listening to any agent yet",
                                             detail: "Connect Claude Code or Codex in Settings, and \(status.name) will notice them.",
                                             action: openSettings, inline: true)])
        } else if status.sessions.isEmpty {
            NoticeStrip(notices: [PaneNotice(icon: "moon.zzz.fill", tone: Theme.inkSoft, title: "No agents awake",
                                             detail: "Start \(heard.map(\.displayName).joined(separator: " or ")) and \(status.name) will notice.",
                                             inline: true)])
        } else {
            let rows = KeyedSession.sorted(status.sessions)
            Card(padding: Card<EmptyView>.rows) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        VStack(spacing: 0) {
                            if i > 0 { Hairline() }
                            Opens(row.session.thread, radius: Theme.wellRadius, model: model) {
                                SessionRow(session: row.session)
                            }
                        }
                    }
                }
            }
            // Rows coming, going, changing status and moving spring into
            // place. A row's latest call changes with every one an agent
            // makes, and springing the list each time would lay the popover
            // out on every frame while agents work, so that text just changes.
            .animation(.boopPop, value: rows.map { [$0.id, "\($0.session.status)", "\($0.session.dismissed)"] })
        }
    }

    // MARK: Notices

    /// Jev not helping, by what the key's owner can do about it; Jev's
    /// own words behind Details. Boop carries on without it.
    private func brainNotice(_ trouble: BrainTrouble) -> PaneNotice {
        let meanwhile = "\(model.name) carries on without it."
        let (title, detail, action): (String, String, NoticeAction?) = switch trouble.kind {
        case .credit: ("Jev is out of credit", "Top up your Jev account at TypeSafe. Until then, \(meanwhile)",
                       ("Jev's docs", { NSWorkspace.shared.open(AppModel.jevDocs) }))
        case .key: ("Jev didn't accept your key", "Check the Jev API key in Settings. Until then, \(meanwhile)", openSettings)
        case .failing: ("Jev isn't answering", "Until it does, \(meanwhile)", nil)
        }
        return PaneNotice(icon: "exclamationmark.triangle.fill", tone: Theme.clayInk, title: title, detail: detail,
                          action: action, more: trouble.why)
    }

    private var openSettings: NoticeAction {
        ("Open Settings", { model.pane = .settings })
    }
}

extension Theme {
    /// The needs-you card's amber wash over a card: twice a toned card's,
    /// so it reads on light paper (`Boop --snapshots` checks its text).
    static let needsYouTint = 0.16
}

// MARK: - Notices

/// A notice's button: its label, and what it does.
typealias NoticeAction = (String, () -> Void)

/// One trouble, or one empty state: what's up in a line, its plain words
/// and the raw detail behind Details (or the words in place, `inline`), a
/// button for what the person can do about it, and a cross if it can go.
struct PaneNotice: Identifiable {
    let icon: String
    let tone: Color
    let title: String
    let detail: String
    var action: NoticeAction? = nil
    var more: String? = nil
    var dismiss: (() -> Void)? = nil
    var inline = false
    var id: String { title }
}

/// Every notice in one card, a line each with its one action; two show,
/// and "N more" opens the rest in place. Details opens in place too.
struct NoticeStrip: View {
    let notices: [PaneNotice]
    /// Whether the rest are open, by this key, the same in every copy (as
    /// Details are): FittedScroll lays its content out more than once.
    var foldKey = ""
    @ObservedObject private var open = OpenDetails.shared

    /// How many show before "N more"; never "1 more", which costs a line.
    static let shown = 2

    /// The key a model's notices fold under, for a snapshot to open them.
    @MainActor static func foldKey(_ model: AppModel) -> String { "notices@\(ObjectIdentifier(model).hashValue)" }

    var body: some View {
        let all = notices.count <= Self.shown + 1 || (!foldKey.isEmpty && open.texts.contains(foldKey))
        let visible = all ? notices : Array(notices.prefix(Self.shown))
        Card(padding: Card<EmptyView>.rows) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, notice in
                    if i > 0 { Hairline() }
                    NoticeLine(notice: notice)
                }
                // The rest folded under "N more", and folded again under "Show fewer".
                let folds = notices.count > Self.shown + 1
                if folds {
                    Hairline()
                    Button { withAnimation(.boopSettle) { open.toggle(foldKey) } } label: {
                        HStack(spacing: Theme.gapSnug) {
                            Text(all ? "Show fewer" : "\(notices.count - visible.count) more").font(.bodyMedium)
                            Spacer(minLength: 0)
                            Image(systemName: all ? "chevron.up" : "chevron.down").font(.chip)
                        }
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.leading, Theme.gap + Theme.iconColumn + Theme.gapSnug)
                        .padding(.trailing, Theme.gap)
                        .frame(minHeight: Theme.target + Theme.gapSnug)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(all ? "Show fewer notices" : "Show \(notices.count - visible.count) more notices")
                }
            }
        }
        .transition(.opacity)
    }
}

/// One notice's line: icon, title, then its action and Details; the cross
/// over the corner, costing the title alone its width.
private struct NoticeLine: View {
    let notice: PaneNotice
    @ObservedObject private var open = OpenDetails.shared

    /// Open or not by its words, as Details are.
    private var shown: Bool {
        open.texts.contains(notice.detail) || notice.more.map(open.texts.contains) == true
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
            Image(systemName: notice.icon).font(.body).foregroundStyle(notice.tone)
                .frame(width: Theme.iconColumn)
            VStack(alignment: .leading, spacing: Theme.hair) {
                Text(notice.title).font(.bodyStrong)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, notice.dismiss != nil ? Theme.gapSnug + Theme.gapTight : 0)
                if notice.inline {
                    Text(notice.detail).caption().fixedSize(horizontal: false, vertical: true)
                }
                if notice.action != nil || !notice.inline {
                    HStack(spacing: Theme.gap) {
                        if let action = notice.action {
                            Button(action.0, action: action.1).buttonStyle(.row)
                        }
                        if !notice.inline {
                            Button { withAnimation(.boopSettle) { toggle() } } label: {
                                HStack(spacing: Theme.gapTight) {
                                    Text("Details")
                                    Image(systemName: shown ? "chevron.down" : "chevron.right").font(.chip)
                                }
                            }
                            .buttonStyle(.wordLink(Theme.inkSoft))
                            .accessibilityLabel(shown ? "Hide details" : "Details")
                        }
                    }
                    .padding(.top, Theme.hair)
                }
                if shown, !notice.inline {
                    Text(notice.detail).caption()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.hair)
                    if let more = notice.more {
                        // The raw words, as a system or a tool said them.
                        Text(more).font(.mono).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(Theme.gapSnug)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
                            .padding(.top, Theme.gapTight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
        .overlay(alignment: .topTrailing) {
            if let dismiss = notice.dismiss {
                Button(action: { withAnimation(.boopSettle) { dismiss() } }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.quietIcon)
                .padding(Theme.gapTight)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    private func toggle() {
        if shown {
            if open.texts.contains(notice.detail) { open.toggle(notice.detail) }
            if let more = notice.more, open.texts.contains(more) { open.toggle(more) }
        } else {
            open.toggle(notice.detail)
        }
    }
}

// MARK: - Parts

func agentSymbol(_ short: String) -> String {
    switch short {
    case "claude": "chevron.left.forwardslash.chevron.right"
    case "codex": "curlybraces"
    default: "terminal"
    }
}

/// A card or row that opens `thread` on a click, where it runs;
/// as it was when there's nowhere to open it.
struct Opens<Content: View>: View {
    let thread: ThreadRef?
    let radius: CGFloat
    @ObservedObject var model: AppModel
    @ViewBuilder var content: Content

    init(_ thread: ThreadRef?, radius: CGFloat, model: AppModel, @ViewBuilder content: () -> Content) {
        self.thread = thread
        self.radius = radius
        self.model = model
        self.content = content()
    }

    var body: some View {
        if let thread, let target = ThreadLink.target(thread) {
            Button { model.runtime?.openThread(thread) } label: { content }
                .buttonStyle(OpensButtonStyle(radius: radius))
                .help(openVerb(target).prefix(1).uppercased() + openVerb(target).dropFirst())
        } else {
            content
        }
    }

}

/// What a click on a session does, after "Click to".
@MainActor func openVerb(_ target: ThreadLink.Target) -> String {
    switch target {
    case .url(let url) where url.hasPrefix("claude:"): "open it in Claude"
    case .url(let url) where url.hasPrefix("codex:"): "open it in Codex"
    case .url: "open it"
    case .app(let id): "switch to " + appName(id)
    case .terminal(let app, _): "open its tab in " + appName(app)
    }
}

/// The needs-you card's button: where a click opens the session.
@MainActor func openLabel(_ target: ThreadLink.Target) -> String {
    switch target {
    case .url(let url) where url.hasPrefix("claude:"): "Open in Claude"
    case .url(let url) where url.hasPrefix("codex:"): "Open in Codex"
    case .url: "Open it"
    case .app(let id): "Open in " + appName(id)
    case .terminal(let app, _): "Open in " + appName(app)
    }
}

/// An app's name by its bundle ID, as Finder shows it. Kept once found: a
/// row asks for it at every status, and each look-up is LaunchServices'.
@MainActor func appName(_ id: String) -> String {
    if let name = appNames[id] { return name }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return "its app" }
    let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    appNames[id] = name
    return name
}

@MainActor private var appNames: [String: String] = [:]

/// A session keyed by its agent, project and thread and which of those
/// sessions it is, so a row that changes status moves, instead of the row
/// in its old place crossfading to another project.
struct KeyedSession: Identifiable {
    let id: String
    let session: SessionSummary

    static func rows(_ sessions: [SessionSummary]) -> [KeyedSession] {
        var seen: [String: Int] = [:]
        return sessions.map { s in
            let place = "\(s.agent):" + (s.workspace.map { "\(s.project)/\($0)" } ?? s.project)
            let n = seen[place, default: 0]
            seen[place] = n + 1
            return KeyedSession(id: "\(place)#\(n)", session: s)
        }
    }

    /// The rows by need: needs you, then dismissed, working and idle; each
    /// kind in the order the runtime gives it.
    static func sorted(_ sessions: [SessionSummary]) -> [KeyedSession] {
        func need(_ s: SessionSummary) -> Int {
            switch s.status {
            case .waiting: s.dismissed ? 1 : 0
            case .working: 2
            case .idle: 3
            }
        }
        return rows(sessions).enumerated()
            .sorted { (need($0.element.session), $0.offset) < (need($1.element.session), $1.offset) }
            .map(\.element)
    }
}

/// What a session's row and the needs-you card call it: the thread's name,
/// its project under it; with no name yet, its project. One with neither a
/// name nor a folder is an untitled session.
func rowTitle(project: String, name: String?) -> (title: String, project: String?) {
    let project = project.isEmpty || project == "unknown" ? nil : project
    if let name, !name.isEmpty { return (name, project) }
    return (project ?? "Untitled session", nil)
}

/// One session in the list: its name in two lines at most, where it runs
/// in one, cut in the middle, and what it's doing, the agent's name first
/// (its latest call's word, its to-dos and for how long). Needs you wears a
/// solid amber chip and an amber bar; working a soft word and its lane's
/// colour, as on the board; idle no word and its colour faint, as its
/// hollow pip. The whole text is in its help.
struct SessionRow: View {
    let session: SessionSummary

    private var status: SessionSummary.Status { session.status }

    private var bar: Color? {
        switch status {
        case .waiting where session.dismissed: Theme.amberSignal.opacity(0.4)
        case .waiting: Theme.amberSignal
        case .working: session.slot.flatMap(Theme.lane) ?? Theme.inkFaint
        case .idle: session.slot.flatMap(Theme.lane)?.opacity(0.35)
        }
    }

    private var agent: String { Agent(rawValue: session.agent)?.displayName ?? session.agent }

    /// The agent, then its state unless working, its latest call's word,
    /// its to-dos and how long it's waited, worked or rested, at `now`.
    private func doing(at now: Date) -> String {
        var parts = [agent]
        switch status {
        case .waiting: parts.append(session.dismissed ? "dismissed" : "waiting")
        case .idle: parts.append("idle")
        case .working: break
        }
        if let card = session.card { parts.append(card) } else if let word = session.word { parts.append(word) }
        if let todo = session.todo { parts.append("\u{2713} \(todo.text)") }
        if let since = session.since { parts.append(SessionRow.span(now.timeIntervalSince(since))) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// A while, as the row says it: `<1m`, `12m`, `3h`, `2d`.
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes < 24 * 60 ? "\(minutes / 60)h" : "\(minutes / (24 * 60))d"
    }

    @ViewBuilder private var chip: some View {
        switch status {
        // Still waiting, but you put it away: it no longer shows on Boop.
        case .waiting where session.dismissed: Text("dismissed").font(.chip).foregroundStyle(Theme.inkSoft)
        case .waiting: Chip("needs you", tone: Theme.amber, solid: true)
        case .working: Text("working").font(.chip).foregroundStyle(Theme.inkSoft)
        case .idle: EmptyView()
        }
    }

    var body: some View {
        let (title, project) = rowTitle(project: session.project, name: session.name)
        let place = [project, session.workspace].compactMap { $0 }.joined(separator: " \u{00B7} ")
        HStack(spacing: Theme.gapSnug) {
            VStack(alignment: .leading, spacing: Theme.hair) {
                Text(title).font(.bodyMedium)
                    .lineLimit(2)  // cut: whole in .help
                    .fixedSize(horizontal: false, vertical: true)
                if !place.isEmpty {
                    Text(place).caption()
                        .lineLimit(1).truncationMode(.middle)  // cut: whole in .help
                }
                // The time moves on as the row shows, a tick a half-minute.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(doing(at: context.date))
                        .font(.mono).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chip
        }
        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
        .overlay(alignment: .leading) {
            if let bar {
                RoundedRectangle(cornerRadius: Theme.barRadius).fill(bar)
                    .frame(width: 3).padding(.vertical, Theme.gapSnug).padding(.leading, Theme.gapTight)
            }
        }
        .contentShape(Rectangle())
        .help([title, place].filter { !$0.isEmpty }.joined(separator: "\n"))
        .accessibilityElement(children: .combine)
    }
}

/// How Boop feels and why, in plain words, so a face never needs decoding:
/// the mood, then why it feels so, how awake it is, its wish, and what it's up to, which
/// the board doesn't caption: what its face is doing to pass the time,
/// else why it's doing what it's doing. With none of those, nothing: the
/// header already names the mood.
struct ReasonLines: View {
    @ObservedObject var feed: SlimeFeed
    let name: String
    let mood: String
    let wish: String?
    let why: String?
    let doing: String?
    let energy: String?

    private var lines: [String] {
        [why, energy, wish, feed.passing.flatMap { Narration.passing($0, in: CharacterPack.active.named(name)) } ?? doing].compactMap { $0 }
    }

    var body: some View {
        if !lines.isEmpty {
            PaneSection("Mood") {
                Card {
                    VStack(alignment: .leading, spacing: Theme.hair) {
                        Text(mood.prefix(1).uppercased() + mood.dropFirst()).font(.bodyStrong)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(lines, id: \.self) { line in
                            Text(line).font(.body).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .animation(.boopSettle, value: lines)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The overview's tabs, as a segmented control: the one open raised on
/// the well. ⌘1, ⌘2 and ⌘3 open them too.
struct TabBar: View {
    @Binding var tab: Tab
    /// Its height, with the gap over it.
    static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: Theme.hair) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, each in
                let on = each == tab
                Button { withAnimation(.boopSettle) { tab = each } } label: {
                    Text(each.title)
                        .font(on ? .bodyStrong : .bodyMedium)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                        .padding(.horizontal, Theme.gapTight).padding(.vertical, Theme.gapTight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: Theme.target)
                        .background {
                            if on {
                                // Raised off the well: paper in light, a step
                                // lighter in dark, where paper reads as a hole.
                                RoundedRectangle(cornerRadius: Theme.chipRadius).fill(Theme.lifted)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.hairline, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Theme.hair)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
    }
}
