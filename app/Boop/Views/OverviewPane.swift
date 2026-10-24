import AgentHooks
import AppKit
import BoopKit
import SwiftUI

/// Overview, top to bottom: Boop and how things are, who needs you, and
/// every session by agent. Controls live in Settings; the one exception is
/// the mic button.
struct OverviewPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            FittedScroll(maxHeight: maxHeight - 76) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    if let error = model.startError {
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "Boop couldn't start", error,
                               action: ("Show boop.log", model.showLog))
                    }
                    if model.status?.uncleanExit == true {
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "\(model.name) stopped unexpectedly",
                               "It didn't close properly last time. A bug report keeps what it knew, with macOS's crash report if there is one.",
                               action: ("Save a bug report", model.saveReport)) {
                            model.runtime?.dismissUncleanExit()
                        }
                    }
                    if model.noKey, !model.noKeyDismissed {
                        notice("key.fill", Theme.inkSoft, "\(model.name) can't react yet",
                               "Add a Jev API key in Settings, and \(model.name) reacts to what your agents do and answers when you talk.",
                               action: openSettings) {
                            model.noKeyDismissed = true
                        }
                    }
                    if let trouble = model.status?.brainTrouble {
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "Jev isn't answering",
                               Self.brainProblem(trouble))
                    }
                    if let why = model.status?.micTrouble {
                        notice("mic.slash.fill", Theme.clayInk, "\(model.name) can't hear you", why) {
                            model.dismissMicTrouble()
                        }
                    }
                    if model.restartAgents {
                        notice("arrow.clockwise", Theme.inkSoft, "Restart your agent sessions",
                               "Open sessions pick up Boop's hooks when they restart.") {
                            model.restartAgents = false
                        }
                    }
                    // A change that failed, at setup or in Settings, until it's dismissed
                    // or the hooks change.
                    ForEach(Agent.allCases.filter { model.hookErrors[$0] != nil && !model.hookErrorsDismissed.contains($0) },
                            id: \.self) { agent in
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "Couldn't change \(agent.displayName)'s hooks",
                               model.hookErrors[agent] ?? "", action: openSettings) {
                            model.dismissHookError(agent)
                        }
                    }
                    if let status = model.status {
                        if let attn = status.snapshot.attn { needsYou(attn, status.sessions) }
                        PaneSection(status.sessions.isEmpty ? "Sessions" : "Sessions · \(status.sessions.count)") {
                            sessions(status)
                        }
                        if let growth = status.growth {
                            PaneSection("Growth") { growthCard(growth, daysOld: status.daysOld) }
                        }
                        if !status.diary.isEmpty {
                            PaneSection("Diary") { diaryCard(status.diary) }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gapLoose)
            }
        }
        // The header grows when reminder chips appear. Bound the whole
        // pane too, so its scroll view gives that extra height back.
        .frame(maxHeight: maxHeight)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            HStack(spacing: Theme.gap) {
                HStack(spacing: Theme.gap) {
                    if let status = model.status, status.connected, status.device?.face == .gel, SlimeFeed.folder != nil {
                        SlimeFace(feed: model.slime, snapshot: status.snapshot, live: model.shown, listening: status.faceListening, size: faceSize)
                    } else {
                        BoopFace(mood: FaceMood(model.status), design: model.status?.snapshot.mood ?? MoodOutput.initial,
                                 size: faceSize)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            // The name comes first: a long one shrinks a little
                            // before it's cut, and the mood shows only whole,
                            // where there's room for it.
                            Text(model.name).font(.boop(18)).lineLimit(1).minimumScaleFactor(0.8)
                                .layoutPriority(1)
                            if let mood = model.status?.snapshot.mood {
                                ViewThatFits(in: .horizontal) {
                                    moodLabel(mood).padding(.leading, Theme.gap)
                                    Color.clear.frame(width: 0, height: 0)
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            StateDot(tone: tone, pulsing: live)
                            Text(model.headline).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        .animation(.boopSettle, value: model.headline)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if model.status != nil {
                    VStack(alignment: .trailing, spacing: 6) {
                        deviceLine
                        talkButton
                    }
                }
            }
            // Under the name, the full width of the popover, so the chips
            // never squeeze each other or the device line.
            chips.padding(.leading, faceSize + Theme.gap)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Theme.gapLoose)
    }

    private let faceSize: CGFloat = 46

    /// Boop's mood in words, labelled, so it doesn't rest on telling the
    /// faces apart. The face already draws in the mood's designs.
    private func moodLabel(_ mood: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Mood").foregroundStyle(Theme.inkSoft)
            Text(mood.capitalized).fontWeight(.semibold).foregroundStyle(Theme.inkSoft)
                .contentTransition(.opacity)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .fixedSize()
        .animation(.boopSettle, value: mood)
        .accessibilityElement(children: .combine)
    }

    /// Small reminders of what's set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is the usual.
    @ViewBuilder private var chips: some View {
        if let status = model.status {
            let s = status.snapshot
            let all: [(String, String)?] = [
                status.personality != .default ? ("bubble.left.and.bubble.right.fill", status.personality.rawValue.capitalized) : nil,
                s.vol == 0 ? ("speaker.slash.fill", "Muted") : nil,
            ]
            let chips = all.compactMap { $0 }
            if !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.1) { icon, text in
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                            Text(text)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.well, in: Capsule())
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// Whether Boop's body is connected, as plain words, so it doesn't look
    /// like a button. Which board it is stays out of sight. With several
    /// buddies, each one's name, its dot saying whether its board is there.
    @ViewBuilder private var deviceLine: some View {
        if let buddies = model.status?.buddies, !buddies.isEmpty {
            HStack(spacing: 8) {
                ForEach(buddies, id: \.id) { b in
                    HStack(spacing: 4) {
                        Circle().fill(b.connected ? Theme.sage : Theme.inkFaint).frame(width: 6, height: 6)
                        Text(b.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    .help("\(b.name), on the \(b.id): \(b.connected ? "connected" : "not connected"), \(b.snapshot.mood)")
                }
            }
            .fixedSize()
            .padding(.trailing, 2)
        } else {
            oneDevice
        }
    }

    private var oneDevice: some View {
        let device = model.device
        return HStack(spacing: 5) {
            Circle().fill(device.connected ? Theme.sage : Theme.inkFaint).frame(width: 6, height: 6)
            Text(device.short)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(device.trouble ? Theme.clayInk : Theme.inkSoft)
        }
        .fixedSize()
        .padding(.trailing, 2)
        .help(device.detail)
        .animation(.boopSettle, value: device.short)
    }

    /// Push-to-talk from the Mac: click to talk, click
    /// again to send. The device's BOOT button does the same while held.
    private var talkButton: some View {
        let on = model.listening
        return Button(action: model.toggleTalk) {
            // One width for both words, so the button doesn't jump.
            Label(on ? "Send" : "Talk", systemImage: on ? "arrow.up" : "mic.fill")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(width: 50)
        }
        .buttonStyle(RowButtonStyle(filled: on))
        .fixedSize()
        .help(on ? "Stop listening and send what \(model.name) heard"
                 : model.noKey ? "Talk to \(model.name) with the Mac's microphone. Only Jev answers, so this needs a Jev API key"
                 : "Talk to \(model.name) with the Mac's microphone. It stops by itself after 30 seconds")
        .accessibilityLabel(on ? "Stop listening and send" : "Talk to \(model.name)")
        .animation(.boopSettle, value: on)
    }

    private var tone: Color {
        if model.listening { return Theme.recording }
        return switch FaceMood(model.status) {
        case .needsYou: Theme.amber
        case .working: Theme.inkSoft
        case .idle, .happy, .asleep, .cheeky, .stopped: Theme.inkFaint
        }
    }

    private var live: Bool {
        let mood = FaceMood(model.status)
        return model.listening || mood == .working || mood == .needsYou
    }

    // MARK: Growth

    /// Boop's stage and XP: the stage's name, how far
    /// through it, and what's left to the next.
    private func growthCard(_ growth: Growth, daysOld: Int?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(growth.name).font(.system(size: 12, weight: .semibold))
                    Text("Stage \(growth.stage) of \(Growth.stages.count)")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                    Text("\(growth.xp.formatted()) XP").font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
                .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.well)
                        Capsule().fill(Theme.amber).frame(width: max(6, geo.size.width * growth.progress))
                    }
                }
                .frame(height: 6)
                .animation(.boopSettle, value: growth.progress)
                Text((growth.nextAt.map { "\(($0 - growth.xp).formatted()) XP to \(Growth.stages[growth.stage].name)" }
                      ?? "Fully grown") + (daysOld.map { " · \($0 == 1 ? "1 day" : "\($0) days") old" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Diary

    /// The diary's last week: a line a day, newest first.
    private func diaryCard(_ lines: [Runtime.Status.DiaryLine]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                ForEach(lines) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.day).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft).monospacedDigit()
                        Text(entry.line).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Needs you

    /// The card names the session that has waited longest, as the device
    /// does, but in full: the snapshot's project and thread name are cut to
    /// fit the device. The session list puts it first.
    /// A click opens it, as a tap on the board's needs-you screen does.
    private func needsYou(_ attn: StateSnapshot.Attention, _ sessions: [SessionSummary]) -> some View {
        let waiting = sessions.first { $0.status == .waiting }
        let project = waiting?.project ?? attn.project
        let name = waiting?.name ?? attn.name
        let agent = Agent(rawValue: attn.agent)?.displayName ?? attn.agent
        let opens = waiting?.thread.flatMap(ThreadLink.target)
        return Opens(waiting?.thread, radius: Theme.cardRadius, model: model) {
            needsYouCard(attn, project: project, name: name, workspace: waiting?.workspace,
                         hint: "\(agent) is waiting for you. " + (opens.map { "Click to \(openVerb($0))." } ?? "Answer it in its window."))
        }
        .overlay(alignment: .bottomTrailing) {
            // Hides the request on Boop, as a finger held on the needs-you
            // screen does; the agent still waits. It names the request the
            // card shows, so one that took its place since isn't dismissed
            // unseen.
            if let thread = waiting?.thread {
                Button("Dismiss") { model.runtime?.dismiss(thread, request: attn.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.amberInk)
                    .padding(Theme.gapSnug + 2)
                    .help("Stop showing this on \(model.status?.name ?? "Boop"). \(agent) still waits.")
            }
        }
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        .animation(.boopPop, value: project)
    }

    /// The project and its thread on the first line, as a session's row has
    /// them, so the thread is cut before the project; which agent it is,
    /// in the hint.
    private func needsYouCard(_ attn: StateSnapshot.Attention, project: String, name: String,
                              workspace: String?, hint: String) -> some View {
        Card(tone: Theme.amber) {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(projectName(project))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            .layoutPriority(1)
                        if let workspace { ThreadName(workspace) }
                    }
                    if !name.isEmpty {
                        Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    }
                    Text(hint)
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                if attn.more > 0 {
                    Text("+\(attn.more) more").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.amberInk)
                }
            }
        }
    }

    // MARK: Sessions

    /// Sessions reach Boop only through the hooks, so with none connected
    /// the list can't promise any, and says where to connect them.
    @ViewBuilder private func sessions(_ status: Runtime.Status) -> some View {
        let heard = Agent.allCases.filter { model.hooks[$0] == .installed || model.hooks[$0] == .outdated }
        if status.sessions.isEmpty, heard.isEmpty {
            notice("ear", Theme.inkSoft, "\(status.name) isn't listening to any agent yet",
                   "Connect Claude Code or Codex in Settings, and \(status.name) will notice them.", action: openSettings)
        } else if status.sessions.isEmpty {
            Card {
                HStack(spacing: Theme.gapSnug + 2) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No agents awake").font(.system(size: 12, weight: .medium))
                        Text("Start \(heard.map(\.displayName).joined(separator: " or ")) and \(status.name) will notice.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            // A fixed order, so a group doesn't jump to the top when one of
            // its sessions starts waiting and back when it stops.
            let agents = Agent.allCases.filter { a in status.sessions.contains { $0.agent == a.rawValue } }
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(agents, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 5) {
                        // A fixed icon width, so the names line up.
                        HStack(spacing: 6) {
                            Image(systemName: agentSymbol(agent.rawValue)).frame(width: 18)
                            Text(agent.displayName)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        ForEach(KeyedSession.rows(status.sessions.filter { $0.agent == agent.rawValue })) { row in
                            Opens(row.session.thread, radius: Theme.wellRadius, model: model) {
                                SessionRow(project: row.session.project,
                                           thread: row.session.name ?? row.session.workspace,
                                           status: row.session.status)
                            }
                        }
                    }
                }
            }
            .animation(.boopPop, value: status.sessions)
        }
    }

    // MARK: Notices

    /// What "Jev isn't answering" says, in plain words, by what the person
    /// can do about it.
    static func brainProblem(_ trouble: BrainTrouble) -> String {
        let meanwhile = "Until Jev answers again, Boop only reacts by its own rules."
        return switch trouble.kind {
        case .credit: "Jev's account is out of credit (\(trouble.why)). Top it up at TypeSafe. \(meanwhile)"
        case .key: "Jev didn't accept the API key (\(trouble.why)). Check the key in Settings. \(meanwhile)"
        case .failing: "The last \(trouble.inARow) tries failed (\(trouble.why)). \(meanwhile)"
        }
    }

    private var openSettings: (String, () -> Void) {
        ("Open Settings", { model.pane = .settings })
    }

    /// A notice card: what's up, in a line and a few words, with a button
    /// for what the person can do about it, and a cross if it can go.
    private func notice(_ icon: String, _ tone: Color, _ title: String, _ detail: String,
                        action: (String, () -> Void)? = nil, dismiss: (() -> Void)? = nil) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tone).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let action {
                        Button(action.0, action: action.1).buttonStyle(.row).padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
                if let dismiss {
                    Button(action: { withAnimation(.boopSettle) { dismiss() } }) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.quiet)
                    .padding(.top, -4).padding(.trailing, -6)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .transition(.opacity)
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
func openVerb(_ target: ThreadLink.Target) -> String {
    switch target {
    case .url(let url) where url.hasPrefix("claude:"): "open it in Claude"
    case .url(let url) where url.hasPrefix("codex:"): "open it in Codex"
    case .url: "open it"
    case .app(let id): "switch to " + appName(id)
    case .terminal(let app, _): "open its tab in " + appName(app)
    }
}

/// An app's name by its bundle ID, as Finder shows it.
func appName(_ id: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return "its app" }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

/// A session keyed by its project and thread and which of those sessions
/// it is, so a row that changes status moves, instead of the row in its old
/// place crossfading to another project.
struct KeyedSession: Identifiable {
    let id: String
    let session: SessionSummary

    static func rows(_ sessions: [SessionSummary]) -> [KeyedSession] {
        var seen: [String: Int] = [:]
        return sessions.map { s in
            let place = s.workspace.map { "\(s.project)/\($0)" } ?? s.project
            let n = seen[place, default: 0]
            seen[place] = n + 1
            return KeyedSession(id: "\(place)#\(n)", session: s)
        }
    }
}

/// A session's project as the popover names it.
func projectName(_ project: String) -> String {
    project.isEmpty ? "Unknown project" : project
}

/// A thread's name after its project, small and faint: which worktree or
/// branch, when a project has several sessions.
struct ThreadName: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.inkSoft)
            .lineLimit(1).truncationMode(.tail)
    }
}

/// One session: the project, its thread, and its status in a chip. The tone also runs
/// down a thin bar on the leading edge, so the amber of a waiting one stands
/// out in a column of greys.
struct SessionRow: View {
    let project: String
    var thread: String?
    let status: SessionSummary.Status

    private var tone: Color {
        switch status {
        case .waiting: Theme.amberInk
        case .working: Theme.ink
        case .idle: Theme.inkSoft
        }
    }

    private var bar: Color {
        switch status {
        case .waiting: Theme.amber
        case .working: Theme.inkSoft
        case .idle: Theme.hairlineStrong
        }
    }

    private var label: String {
        switch status {
        case .waiting: "needs you"
        case .working: "working"
        case .idle: "idle"
        }
    }

    var body: some View {
        HStack(spacing: Theme.gapSnug) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(projectName(project))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                if let thread { ThreadName(thread) }
            }
            Spacer(minLength: Theme.gapTight)
            StatusChip(text: label, tone: tone)
        }
        .padding(.leading, 13).padding(.trailing, 8).padding(.vertical, 7)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(bar).frame(width: 3).padding(.vertical, 6).padding(.leading, 1)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
