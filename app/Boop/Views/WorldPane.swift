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
        if let snapshot = world.link.snapshot {
            tiles(snapshot)
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                WorldBand(buddies: snapshot.buddies, you: world.utcOffset,
                          pick: Binding(get: { model.worldPick }, set: { pick in withAnimation(.boopSettle) { model.worldPick = pick } }))
                Text("Buddies around the world, by time zone. Tap one.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
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
                Text(n.formatted()).font(.boop(17, .bold)).monospacedDigit()
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: A buddy's card

    private func card(_ buddy: World.Buddy, world: Runtime.WorldStatus) -> some View {
        let canSend = world.inWorld
        let sent = model.worldSent[buddy.id]
        let kinds: [World.GestureKind] = [.wave, .boop, .heart] + (buddy.activity == .shipping ? [.cheer] : [])
        return Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(buddy.name).font(.system(size: 13, weight: .semibold))
                    Text(" · level \(buddy.level)").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: Theme.gapSnug)
                    Button { withAnimation(.boopSettle) { model.worldPick = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.quiet)
                    .padding(.top, -4).padding(.trailing, -6)
                    .accessibilityLabel("Close")
                }
                Text(Self.whereAndWhat(buddy)).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(kinds, id: \.self) { kind in
                        Button { model.sendGesture(kind, to: buddy.id) } label: {
                            // Snug, so four fit on a line: Cheer's too, for a ship.
                            HStack(spacing: 4) {
                                Image(systemName: Self.symbol(kind))
                                Text(Self.label(kind))
                            }
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.row)
                        .disabled(!canSend || sent == .sending(kind))
                    }
                }
                if let words = sentWords(sent, buddy: buddy, world: world) {
                    Text(words).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Where it is, what it's doing and its time there: "Europe and
    /// Africa · coding · 2:14 PM".
    static func whereAndWhat(_ buddy: World.Buddy, now: Date = Date()) -> String {
        var parts = [World.Region(offset: buddy.utcOffset)?.name, buddy.activity.words]
        if let offset = buddy.utcOffset, let zone = TimeZone(secondsFromGMT: offset * 60) {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = zone
            parts.append(now.formatted(style))
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Under the buttons: why they can't be pressed, or how the last one went.
    private func sentWords(_ sent: AppModel.WorldSend?, buddy: World.Buddy, world: Runtime.WorldStatus) -> String? {
        if !world.on { return "\(model.name) is keeping to itself, so it can't say hi. Switch the world on in Settings." }
        if !world.inWorld { return "\(model.name) is still finding its way into the world. Try again in a moment." }
        switch sent {
        case .sent?: return buddy.activity == .asleep ? "Sent. \(buddy.name) will see it when it wakes."
                                                       : "Sent. \(buddy.name) will see it in a moment."
        case .failed?: return "That didn't go through. Try again in a little while."
        default: return nil
        }
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

    /// What other buddies did, newest first; those that didn't play on the
    /// board (too many boops in an hour) summed up in one line.
    private func arrivals(_ today: [WorldLink.Arrival]) -> some View {
        let played = today.filter(\.plays)
        let more = today.filter { !$0.plays }.reduce(0) { $0 + $1.counts.reduce(0) { $0 + $1.n } }
        return VStack(alignment: .leading, spacing: Theme.gapSnug) {
            if today.isEmpty {
                NoteCard("Nothing yet today.")
            }
            ForEach(played) { arrival in
                Card(padding: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        Image(systemName: Self.symbol(arrival.counts.first?.kind ?? .boop))
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft).frame(width: 16)
                        Text(arrival.sentence(name: model.name)).font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(arrival.at.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                            .fixedSize()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if more > 0 {
                Text(played.isEmpty ? "\(more) hellos from other buddies today." : "And \(more) more today.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .padding(.leading, 2)
            }
        }
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
