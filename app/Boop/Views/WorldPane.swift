import BoopKit
import SwiftUI

/// The World tab: the live numbers, the band of time zones with a buddy's
/// card on a click, what other buddies did for Boop today, and the regions.
/// The world is fetched only while this tab is in sight (`AppModel.tab`).
struct WorldPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            if let world = model.status?.world {
                content(world)
            } else {
                NoteCard("The world isn't reachable from here.")
            }
        }
    }

    @ViewBuilder private func content(_ world: Runtime.WorldStatus) -> some View {
        if !world.on {
            privateNote
        } else if !world.inWorld {
            Label("Joining the world…", systemImage: "globe")
                .caption()
                .padding(.leading, 2)
        }
        if let snapshot = world.link.snapshot {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                if world.link.trouble != nil {
                    Label("The world isn't answering, so this may be out of date.", systemImage: "exclamationmark.triangle")
                        .caption()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 2)
                }
                tiles(snapshot)
            }
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                WorldBand(buddies: snapshot.buddies, awake: snapshot.awake, me: world.link.id,
                          you: world.utcOffset, youIn: world.inWorld,
                          pick: Binding(get: { model.worldPick }, set: { pick in withAnimation(.boopSettle) { model.worldPick = pick } }))
                Text("Buddies around the world, by time zone. Click one.")
                    .caption()
                    .padding(.leading, 2)
                if let pick = model.worldPick, let buddy = snapshot.buddies.first(where: { $0.id == pick }) {
                    card(buddy, world: world)
                        .transition(.opacity)
                }
            }
        } else if world.link.trouble != nil {
            NoteCard("The world can't be reached just now. \(model.name) will keep trying.")
        } else {
            NoteCard("Looking around the world…")
        }
        PaneSection("For \(model.name) today") { arrivals(world.link.today) }
        if let snapshot = world.link.snapshot {
            PaneSection("Around the world") { regions(snapshot.regions) }
        }
    }

    /// The world is off: Boop is out of it, and the way back in.
    private var privateNote: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.gapSnug) {
                Text("\(model.name) is private. Others can't see or boop it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Open Settings") { model.pane = .settings }
                    .buttonStyle(.row).fixedSize()
            }
        }
    }

    // MARK: The numbers

    private func tiles(_ snapshot: World.Snapshot) -> some View {
        HStack(spacing: Theme.gapSnug) {
            tile(snapshot.awake, "awake")
            tile(snapshot.doing[World.Activity.coding.rawValue] ?? 0, "coding")
            tile(snapshot.today.testsPassed, "tests today")
        }
    }

    private func tile(_ n: Int, _ label: String) -> some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 1) {
                // A big number takes a smaller size rather than wrap or cut.
                ViewThatFits(in: .horizontal) {
                    ForEach([17, 14, 12] as [CGFloat], id: \.self) { size in
                        Text(n.formatted()).font(.boop(size, .bold)).monospacedDigit().fixedSize()
                    }
                }
                Text(label).caption()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: A buddy's card

    private func card(_ buddy: World.Buddy, world: Runtime.WorldStatus) -> some View {
        let isYou = buddy.id == world.link.id
        let sent = model.worldSent[buddy.id] ?? .init()
        let kinds: [World.GestureKind] = [.wave, .boop, .heart] + (buddy.activity == .shipping ? [.cheer] : [])
        return Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(buddy.name).font(.system(size: 13, weight: .semibold))
                    Text(" · level \(buddy.level)" + (isYou ? " · you" : "")).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize()
                }
                .padding(.trailing, 18)
                Text(Self.whereAndWhat(buddy)).caption()
                    .fixedSize(horizontal: false, vertical: true)
                if isYou {
                    Text("This is \(model.name), as other buddies see it.").caption()
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        ForEach(kinds, id: \.self) { kind in
                            let done = sent.sent.contains(kind)
                            Button { model.sendGesture(kind, to: buddy.id) } label: {
                                // Snug, so four fit on a line: Cheer's too, for a ship.
                                HStack(spacing: 4) {
                                    Image(systemName: done ? "checkmark" : Self.symbol(kind))
                                    Text(Self.label(kind))
                                }
                                .fixedSize()
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.row)
                            .disabled(!world.inWorld || model.worldSending || done)
                            .accessibilityLabel(done ? "\(Self.label(kind)), sent" : Self.label(kind))
                        }
                    }
                    if let (words, failed) = sentWords(sent, buddy: buddy, world: world) {
                        Text(words).font(.system(size: 11)).foregroundStyle(failed ? Theme.clayInk : Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { withAnimation(.boopSettle) { model.worldPick = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.quiet)
            .padding(6)
            .accessibilityLabel("Close")
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

    /// Under the buttons: why they can't be pressed, or how the last one
    /// went, and whether that's a failure.
    private func sentWords(_ sent: AppModel.WorldSend, buddy: World.Buddy, world: Runtime.WorldStatus) -> (String, Bool)? {
        if !world.on { return ("\(model.name) is private, so it can't say hi. Turn on the world in Settings.", false) }
        if !world.inWorld { return ("\(model.name) is still finding its way into the world. Try again in a moment.", false) }
        if let kind = sent.sending { return ("Sending a \(kind.rawValue)…", false) }
        if let kind = sent.failed {
            return ("The \(kind.rawValue) didn't go through. Try again in a while.", true)
        }
        if !sent.sent.isEmpty {
            return (buddy.activity == .asleep ? "Sent. \(buddy.name) will see it when it wakes."
                                              : "Sent. \(buddy.name) will see it in a moment.", false)
        }
        return nil
    }

    static func label(_ kind: World.GestureKind) -> String { kind.rawValue.capitalized }

    static func symbol(_ kind: World.GestureKind) -> String {
        switch kind {
        case .wave: "hand.wave.fill"
        case .boop: "hand.point.up.left.fill"
        case .heart: "heart.fill"
        case .cheer: "party.popper.fill"
        }
    }

    // MARK: For Boop today

    /// How many arrivals get a card each; the rest are summed in a line.
    static let arrivalCards = 5

    /// What other buddies did, newest first: the newest few that played on
    /// the board each a card, and everything else, those too and the ones
    /// that didn't play (too many boops in an hour), summed up in one line.
    private func arrivals(_ today: [WorldLink.Arrival]) -> some View {
        let played = today.filter(\.plays)
        let shown = Array(played.prefix(Self.arrivalCards))
        let rest = today.filter { a in !shown.contains { $0.id == a.id } }
        let more = rest.reduce(0) { $0 + $1.counts.reduce(0) { $0 + $1.n } }
        return VStack(alignment: .leading, spacing: Theme.gapSnug) {
            if today.isEmpty {
                NoteCard("Nothing yet today.")
            }
            ForEach(shown) { arrival in
                Card(padding: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        Image(systemName: Self.symbol(arrival.counts.first?.kind ?? .boop))
                            .caption().frame(width: 16)
                        Text(arrival.sentence(name: model.name)).font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(arrival.at.formatted(date: .omitted, time: .shortened))
                            .caption()
                            .fixedSize()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if more > 0 {
                Text(Self.moreLine(more, anyShown: !shown.isEmpty))
                    .caption()
                    .padding(.leading, 2)
            }
        }
    }

    /// "And 4 more today.", or with no cards above it, "1 hello from
    /// another buddy today."
    static func moreLine(_ n: Int, anyShown: Bool) -> String {
        if anyShown { return "And \(n) more today." }
        return n == 1 ? "1 hello from another buddy today." : "\(n) hellos from other buddies today."
    }

    // MARK: Around the world

    private func regions(_ counts: [World.RegionCount]) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(World.Region.allCases.enumerated()), id: \.element) { i, region in
                    if i > 0 { Hairline().padding(.horizontal, 12) }
                    let awake = counts.first { $0.region == region }?.awake ?? 0
                    HStack {
                        Text(region.name).font(.system(size: 12))
                        Spacer()
                        Text(awake == 0 ? "all asleep" : "\(awake.formatted()) awake")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                }
            }
        }
    }
}
