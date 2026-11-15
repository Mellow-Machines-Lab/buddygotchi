import BoopKit
import SwiftUI

/// The World tab: the live numbers, the band of time zones with a buddy's
/// card on a click, and what other buddies did for Boop today. While the
/// world loads, or can't be reached, the layout stays as it will be, with
/// the words on the empty band, so the popover doesn't jump.
/// The world is fetched only while this tab is in sight (`AppModel.tab`).
struct WorldPane: View {
    @ObservedObject var model: AppModel

    /// Under this many buddies the numbers are a sentence, not a card.
    static let small = 20

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            if let world = model.status?.world {
                content(world)
            } else {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    sentence(nil)
                    band(nil, world: nil, message: "The world isn't reachable from here.", trouble: false)
                }
            }
        }
    }

    @ViewBuilder private func content(_ world: Runtime.WorldStatus) -> some View {
        let snapshot = world.link.snapshot
        VStack(alignment: .leading, spacing: Theme.gap) {
            if !world.on { privateNote }
            // One slot for how the world is with you: joining, or out of date.
            if let note = statusNote(world) {
                Label(note, systemImage: world.link.trouble != nil ? "exclamationmark.triangle" : "globe")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Theme.hair)
            }
            if let snapshot, snapshot.total >= Self.small { columns(snapshot) } else { sentence(snapshot) }
            band(snapshot, world: world,
                 message: snapshot != nil ? nil : world.link.trouble != nil
                     ? "The world can't be reached just now. \(model.name) will keep trying." : "Looking around the world…",
                 trouble: snapshot == nil && world.link.trouble != nil)
            if let snapshot, snapshot.total < Self.small {
                Text(Self.firstLine(snapshot.total, name: model.name)).caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Theme.hair)
            }
            if let snapshot, let pick = model.worldPick, let buddy = snapshot.buddies.first(where: { $0.id == pick }) {
                card(buddy, world: world)
                    .transition(.opacity)
            }
        }
        // Not known while the world can't be read: hidden until it can, or something came.
        if snapshot != nil || !world.link.today.isEmpty {
            PaneSection("For \(model.name) today") { arrivals(world.link.today) }
        }
    }

    /// Joining, or the world not answering with an older world on show.
    private func statusNote(_ world: Runtime.WorldStatus) -> String? {
        if world.on, !world.inWorld { return "Joining the world…" }
        if world.link.snapshot != nil, world.link.trouble != nil { return "The world isn't answering, so this may be out of date." }
        return nil
    }

    /// "5 buddies so far. Mochi is one of the first."
    static func firstLine(_ total: Int, name: String) -> String {
        "\(total.formatted()) \(total == 1 ? "buddy" : "buddies") so far. \(name) is one of the first."
    }

    /// The world is off: Boop is out of it, and the way back in.
    private var privateNote: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.gapSnug) {
                Text("\(model.name) is private. Others can't see or say hi to it.")
                    .font(.body).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Open Settings") { model.pane = .settings }
                    .buttonStyle(.row).fixedSize()
            }
        }
    }

    private func band(_ snapshot: World.Snapshot?, world: Runtime.WorldStatus?, message: String?, trouble: Bool) -> some View {
        WorldBand(buddies: snapshot?.buddies ?? [], awake: snapshot?.awake ?? 0, regions: snapshot?.regions,
                  me: world?.link.id, you: world?.utcOffset ?? TimeZone.current.secondsFromGMT() / 60,
                  youIn: world?.inWorld ?? false,
                  pick: Binding(get: { model.worldPick }, set: { pick in withAnimation(.boopSettle) { model.worldPick = pick } }),
                  message: message, trouble: trouble)
    }

    // MARK: The numbers

    /// The three numbers: awake, coding and tests passed today; nil while
    /// the world isn't known.
    static func numbers(_ snapshot: World.Snapshot?) -> [(n: Int?, label: String)] {
        [(snapshot?.awake, "awake"),
         (snapshot.map { $0.doing[World.Activity.coding.rawValue] ?? 0 }, "coding"),
         (snapshot?.today.testsPassed, "tests today")]
    }

    /// A small world's numbers, as one line: "3 awake · 1 coding · 12 tests today".
    private func sentence(_ snapshot: World.Snapshot?) -> some View {
        Self.numbers(snapshot).enumerated().reduce(Text("")) { line, item in
            let (i, number) = item
            return line + Text(i > 0 ? " · " : "").foregroundStyle(Theme.inkSoft)
                + Text(number.n?.formatted() ?? "–").fontWeight(.semibold) + Text(" \(number.label)")
        }
        .font(.lead)
        .padding(.leading, Theme.hair)
        .accessibilityElement(children: .combine)
    }

    /// A large world's numbers: one card, three columns.
    private func columns(_ snapshot: World.Snapshot) -> some View {
        Card(padding: Card<EmptyView>.rows) {
            HStack(spacing: 0) {
                ForEach(Array(Self.numbers(snapshot).enumerated()), id: \.offset) { i, number in
                    if i > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) }
                    VStack(alignment: .leading, spacing: Theme.hair) {
                        // A big number takes a smaller size rather than wrap or cut.
                        ViewThatFits(in: .horizontal) {
                            ForEach([Font.boopTitle, .boopHeading, .boopLabel], id: \.self) { font in
                                Text(number.n?.formatted() ?? "–").font(font).monospacedDigit().fixedSize()
                            }
                        }
                        Text(number.label).caption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.gap)
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: A buddy's card

    /// What saying hi to a buddy sends: the boop, or Cheer while it ships.
    static func gesture(for buddy: World.Buddy) -> World.GestureKind { buddy.activity == .shipping ? .cheer : .boop }

    /// The face a buddy's card shows, by what it's doing.
    static func face(_ activity: World.Activity) -> FaceMood {
        switch activity {
        case .asleep: .asleep
        case .idle, .waiting: .idle
        case .coding, .testing, .shipping: .working
        }
    }

    private func card(_ buddy: World.Buddy, world: Runtime.WorldStatus) -> some View {
        let isYou = buddy.id == world.link.id
        return HStack(alignment: .top, spacing: Theme.gap) {
            BoopFace(mood: Self.face(buddy.activity), size: 32)
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                VStack(alignment: .leading, spacing: Theme.hair) {
                    (Text(buddy.name).font(.bodyStrong) + Text(" · level \(buddy.level.formatted())" + (isYou ? " · you" : ""))
                        .font(.body).foregroundStyle(Theme.inkSoft))
                        .fixedSize(horizontal: false, vertical: true)
                    // Its time there keeps time while the card is open.
                    TimelineView(.everyMinute) { context in
                        Text(Self.whereAndWhat(buddy, now: context.date)).caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, Theme.target)
                if isYou {
                    Text("This is \(model.name), as other buddies see it.").caption()
                        .fixedSize(horizontal: false, vertical: true)
                } else if !world.on {
                    HStack(alignment: .center, spacing: Theme.gapSnug) {
                        Text("\(model.name) is private, so it can't say hi.").caption()
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Open Settings") { model.pane = .settings }.buttonStyle(.row).fixedSize()
                    }
                } else {
                    action(buddy, world: world)
                }
            }
        }
        .padding(Theme.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lifted, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .overlay(alignment: .topTrailing) {
            Button { withAnimation(.boopSettle) { model.worldPick = nil } } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.quietIcon)
            .padding(Theme.gapTight)
            .accessibilityLabel("Close")
        }
    }

    /// The one button, Say hi or Cheer the ship, and beside it how it went.
    private func action(_ buddy: World.Buddy, world: Runtime.WorldStatus) -> some View {
        let kind = Self.gesture(for: buddy)
        let sent = model.worldSent[buddy.id] ?? .init()
        let done = sent.sent.contains(kind)
        let failed = sent.failed == kind
        return HStack(alignment: .center, spacing: Theme.gap) {
            if done {
                Label(kind == .cheer ? "Cheered" : "Said hi", systemImage: "checkmark")
                    .font(.detailStrong).foregroundStyle(Theme.sageInk)
                    .frame(minHeight: Theme.target)
                    .fixedSize()
            } else {
                Button { model.sendGesture(kind, to: buddy.id) } label: {
                    Label(failed ? "Try again" : kind == .cheer ? "Cheer the ship" : "Say hi",
                          systemImage: kind == .cheer ? "party.popper.fill" : "hand.wave.fill")
                }
                .buttonStyle(.rowFilled)
                .fixedSize()
                .disabled(!world.inWorld || model.worldSending)
            }
            if let (words, isFailure) = Self.sentWords(sent, kind: kind, buddy: buddy, world: world, name: model.name) {
                Text(words).caption()
                    .foregroundStyle(isFailure ? Theme.clayInk : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where it is, what it's doing and its time there: "Europe and
    /// Africa · coding · 2:14 PM".
    static func whereAndWhat(_ buddy: World.Buddy, now: Date = Date()) -> String {
        var parts = [World.Region(offset: buddy.utcOffset)?.name, doing(buddy.activity)]
        if let offset = buddy.utcOffset, let zone = TimeZone(secondsFromGMT: offset * 60) {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = zone
            parts.append(now.formatted(style))
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// What a buddy is doing, in the app's words: the wire's idle is resting.
    static func doing(_ activity: World.Activity) -> String {
        activity == .idle ? "resting" : activity.words
    }

    /// Beside the button: why it can't be pressed, or how it went, and
    /// whether that's a failure.
    static func sentWords(_ sent: AppModel.WorldSend, kind: World.GestureKind, buddy: World.Buddy,
                          world: Runtime.WorldStatus, name: String) -> (String, Bool)? {
        if !world.inWorld { return ("\(name) is still finding its way into the world.", false) }
        if sent.failed == kind { return ("That didn't go through.", true) }
        if sent.sending == kind { return nil }
        let later = buddy.activity == .asleep ? "\(buddy.name) will see it when it wakes." : nil
        if sent.sent.contains(kind) { return (later ?? "\(buddy.name) will see it in a moment.", false) }
        return later.map { ($0, false) }
    }

    // MARK: For Boop today

    /// How many arrivals get a row each; the rest are summed in a line.
    static let arrivalCards = 5

    /// What other buddies did, newest first: the newest few that played on
    /// the board each a row of one card, and everything else, those too and
    /// the ones that didn't play (too many in an hour), summed up in one line.
    private func arrivals(_ today: [WorldLink.Arrival]) -> some View {
        let played = today.filter(\.plays)
        let shown = Array(played.prefix(Self.arrivalCards))
        let rest = today.filter { a in !shown.contains { $0.id == a.id } }
        let more = rest.reduce(0) { $0 + $1.counts.reduce(0) { $0 + $1.n } }
        return VStack(alignment: .leading, spacing: Theme.gapSnug) {
            if today.isEmpty {
                NoteCard("Nothing yet today.")
            }
            if !shown.isEmpty {
                Card(padding: Card<EmptyView>.rows) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, arrival in
                            if i > 0 { Hairline().padding(.horizontal, Theme.gap) }
                            HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                                Image(systemName: Self.symbol(arrival.counts.first?.kind ?? .boop))
                                    .caption().frame(width: Theme.iconColumn)
                                (Text(arrival.at.formatted(Self.shortTime)).foregroundStyle(Theme.inkSoft)
                                    + Text("  " + Self.words(arrival, name: model.name)))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if more > 0 {
                Text(Self.moreLine(more, anyShown: !shown.isEmpty))
                    .caption()
                    .padding(.leading, Theme.hair)
            }
        }
    }

    /// The time as its first word: "10:42".
    static let shortTime = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()

    /// An arrival in the person's words: the boop they send as Say hi
    /// arrives as "said hi".
    static func words(_ arrival: WorldLink.Arrival, name: String) -> String {
        arrival.sentence(name: name).replacingOccurrences(of: "booped \(name)", with: "said hi to \(name)")
    }

    static func symbol(_ kind: World.GestureKind) -> String {
        switch kind {
        case .wave, .boop: "hand.wave.fill"
        case .heart: "heart.fill"
        case .cheer: "party.popper.fill"
        }
    }

    /// "And 4 more today.", or with no rows above it, "1 hello from
    /// another buddy today."
    static func moreLine(_ n: Int, anyShown: Bool) -> String {
        if anyShown { return "And \(n) more today." }
        return n == 1 ? "1 hello from another buddy today." : "\(n) hellos from other buddies today."
    }
}
