import BoopKit
import SwiftUI

/// The World tab (plan/xp-league.md §6.3): the week's league, the buddy
/// just ahead of you, how you stand among everyone, and what other buddies
/// did for Boop today. A row opens that buddy's card. The league is fetched
/// only while this tab is in sight (`AppModel.tab`).
struct WorldPane: View {
    @ObservedObject var model: AppModel

    /// The rows the list shows before your own.
    static let shownRows = 10
    /// Under this many buddies with XP, no percent: it says nothing yet.
    static let percentFrom = 50

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
        let league = world.link.league
        VStack(alignment: .leading, spacing: Theme.gap) {
            if !world.on { privateNote }
            if let note = statusNote(world) {
                Label(note, systemImage: world.link.trouble != nil ? "exclamationmark.triangle" : "globe")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Theme.hair)
            }
            if let pick = model.worldPick {
                card(pick, league: league, world: world)
                    .transition(.opacity)
            } else if let league {
                PaneSection(Self.title(league)) { list(league, world: world) }
                if let me = league.me, let line = Self.rival(me) {
                    Card {
                        (Text(line.lead).font(.bodyStrong) + Text(line.rest.map { " " + $0 } ?? "").font(.body))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(Self.standing(league)).caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Theme.hair)
            } else {
                NoteCard(world.link.trouble != nil
                         ? "The world can't be reached just now. \(model.name) will keep trying." : "Looking around the world…")
            }
        }
        // Not known while the world can't be read: hidden until it can, or something came.
        if model.worldPick == nil, league != nil || !world.link.today.isEmpty {
            PaneSection("For \(model.name) today") { arrivals(world.link.today) }
        }
    }

    /// Joining, or the world not answering with an older league on show.
    private func statusNote(_ world: Runtime.WorldStatus) -> String? {
        if world.on, !world.inWorld { return "Joining the world…" }
        if world.link.league != nil, world.link.trouble != nil { return "The world isn't answering, so this may be out of date." }
        return nil
    }

    /// "This week's league · ends in 2 days".
    static func title(_ league: World.League, now: Date = Date()) -> String {
        guard let ends = league.ends else { return "This week's league" }
        let days = Int(ceil(ends.timeIntervalSince(now) / 86_400))
        let when = days <= 1 ? (ends.timeIntervalSince(now) < 12 * 3600 ? "ends today" : "ends tomorrow") : "ends in \(days) days"
        return "This week's league · \(when)"
    }

    /// The line under the list: how you stand among everyone, and how many are awake.
    static func standing(_ league: World.League) -> String {
        let awake = "\(league.awake.formatted()) \(league.awake == 1 ? "is" : "are") awake now."
        if let p = league.me?.topPercent, league.withXP >= percentFrom {
            return "Top \(p)% of \(league.total.formatted()) buddies this week. " + awake
        }
        return "\(league.total.formatted()) \(league.total == 1 ? "buddy" : "buddies") in the world. " + awake
    }

    /// The buddy just ahead, and what would pass it: "37 XP behind Nori." "Two ships would pass it."
    static func rival(_ me: World.League.Me) -> (lead: String, rest: String?)? {
        if let ahead = me.ahead {
            let need = ahead.by + 1
            let ships = (need + Growth.shipXP - 1) / Growth.shipXP, turns = (need + Growth.turnXP - 1) / Growth.turnXP
            let words = ["One", "Two", "Three"]
            let rest = ships <= 3 ? "\(words[ships - 1]) \(ships == 1 ? "ship" : "ships") would pass \(ahead.name)."
                : "\(turns.formatted()) turns would pass \(ahead.name)."
            return (ahead.by == 0 ? "Level with \(ahead.name)." : "\(ahead.by.formatted()) XP behind \(ahead.name).", rest)
        }
        guard me.xpWeek > 0 else { return nil }
        if let behind = me.behind { return ("First, \(behind.by.formatted()) XP ahead of \(behind.name).", nil) }
        return ("First.", nil)
    }

    /// The top rows, then a gap and your own if it's lower.
    private func list(_ league: World.League, world: Runtime.WorldStatus) -> some View {
        let top = Array(league.rows.prefix(Self.shownRows))
        let mine = league.me.flatMap { me in top.contains { $0.place == me.place } ? nil : league.rows.first { $0.place == me.place } }
        let most = max(1, league.rows.first?.xpWeek ?? 1)
        return Card(padding: Card<EmptyView>.rows) {
            VStack(alignment: .leading, spacing: 0) {
                if top.isEmpty {
                    Text("Nobody has earned anything this week yet.").font(.body).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                }
                ForEach(Array(top.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Hairline().padding(.horizontal, Theme.gap) }
                    leagueRow(row, most: most, you: row.id == world.link.id)
                }
                if let mine {
                    Hairline().padding(.horizontal, Theme.gap)
                    Text("…").caption().padding(.horizontal, Theme.gap)
                    leagueRow(mine, most: most, you: true)
                }
                if league.total > top.count + (mine == nil ? 0 : 1) {
                    Hairline().padding(.horizontal, Theme.gap)
                    Text("\((league.total - top.count - (mine == nil ? 0 : 1)).formatted()) more buddies").caption()
                        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                }
            }
        }
    }

    private func leagueRow(_ row: World.League.Row, most: Int, you: Bool) -> some View {
        Button { withAnimation(.boopSettle) { model.worldPick = row.id } } label: {
            HStack(spacing: Theme.gapSnug) {
                Text("\(row.place)").font(.bodyStrong).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    .frame(minWidth: 18, alignment: .trailing)
                Circle().fill(Self.dot(row.activity)).frame(width: 8, height: 8)
                (Text(row.name).font(.bodyStrong) + Text(you ? " · you" : "").font(.body)
                    + Text("  " + Self.doing(row.activity)).font(.body).foregroundStyle(Theme.inkSoft))
                    .lineLimit(1)  // cut: a league row is one line; the whole name is on its card
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(Theme.hairlineStrong).frame(width: 44, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.care).frame(width: 44 * CGFloat(row.xpWeek) / CGFloat(most), height: 5)
                    }
                Text(row.xpWeek.formatted()).font(.bodyStrong).monospacedDigit()
                Image(systemName: "chevron.right").caption()
            }
            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
            .background(you ? Theme.care.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.place). \(row.name)\(you ? ", you" : ""), \(Self.doing(row.activity)), \(row.xpWeek) XP this week")
    }

    /// The dot that says what a buddy is doing now.
    static func dot(_ activity: World.Activity) -> Color {
        switch activity {
        case .coding: Theme.ring
        case .testing: Color(hex: "#A97BD6")
        case .shipping: Theme.sageSignal
        case .waiting: Theme.inkSoft
        case .idle, .asleep: Theme.hairlineStrong
        }
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

    // MARK: A buddy's card

    /// The kinds a card offers: a boop, a wave and a heart, and a cheer while it ships.
    static func gestures(for activity: World.Activity) -> [World.GestureKind] {
        [.boop, .wave, .heart] + (activity == .shipping ? [.cheer] : [])
    }

    /// The face a buddy's card shows, by what it's doing.
    static func face(_ activity: World.Activity) -> FaceMood {
        switch activity {
        case .asleep: .asleep
        case .idle, .waiting: .idle
        case .coding, .testing, .shipping: .working
        }
    }

    /// A buddy's card: who, what it's doing now, its numbers, the buttons,
    /// what's between you two. Before its profile comes, what its row said.
    private func card(_ id: String, league: World.League?, world: Runtime.WorldStatus) -> some View {
        let isYou = id == world.link.id
        let p = world.link.profile.flatMap { $0.id == id ? $0 : nil }
        let row = league?.rows.first { $0.id == id }
        let name = p?.name ?? row?.name ?? "A buddy"
        let activity = p?.activity ?? row?.activity ?? .idle
        return VStack(alignment: .leading, spacing: Theme.gap) {
            Button { withAnimation(.boopSettle) { model.worldPick = nil } } label: {
                Label("League", systemImage: "chevron.left")
            }
            .buttonStyle(.row).fixedSize()
            HStack(alignment: .center, spacing: Theme.gap) {
                BoopFace(mood: Self.face(activity), size: 44)
                    .buddyColor(p?.color ?? row?.color ?? 0)
                VStack(alignment: .leading, spacing: Theme.hair) {
                    Text(name).font(.boopTitle)
                    Text(Self.levelLine(level: p?.level ?? row?.level ?? 1, days: p?.daysInARow ?? 0))
                        .font(.body).foregroundStyle(Theme.inkSoft)
                    if let medals = p?.medals, medals.any { MedalsRow(medals: medals) }
                }
            }
            Card {
                TimelineView(.everyMinute) { context in
                    (Text(Self.doing(activity).prefix(1).uppercased() + Self.doing(activity).dropFirst() + " now.").font(.bodyStrong)
                        + Text(Self.where_(p?.region, offset: p?.utcOffset, now: context.date).map { " " + $0 } ?? "").font(.body))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let p {
                Card(padding: Card<EmptyView>.rows) {
                    VStack(alignment: .leading, spacing: 0) {
                        numberRow("This week", "\(p.week.xp.formatted()) XP · \(Self.ordinal(p.week.place))")
                        Hairline().padding(.horizontal, Theme.gap)
                        numberRow("Today", "\(p.today.turns) turns · \(p.today.ships) \(p.today.ships == 1 ? "ship" : "ships")")
                        Hairline().padding(.horizontal, Theme.gap)
                        numberRow("Best week", "\(p.bestWeek.formatted()) XP")
                    }
                }
            }
            if isYou {
                Text("This is \(model.name), as other buddies see it.").caption()
            } else if !world.on {
                HStack(alignment: .center, spacing: Theme.gapSnug) {
                    Text("\(model.name) is private, so it can't say hi.").caption()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Open Settings") { model.pane = .settings }.buttonStyle(.row).fixedSize()
                }
            } else {
                actions(id, name: name, activity: activity, world: world)
            }
            if !isYou, let between = p?.between, let lines = Optional(Self.youTwo(between, them: name, you: model.name)), !lines.isEmpty {
                PaneSection("You two") {
                    Card(padding: Card<EmptyView>.rows) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                if i > 0 { Hairline().padding(.horizontal, Theme.gap) }
                                HStack(spacing: Theme.gapSnug) {
                                    Text(line.words).font(.body).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let back = line.back, world.on {
                                        let done = model.worldSent[id]?.sent.contains(back) == true
                                        Button(done ? "Sent" : "\(Self.verb(back)) back") { model.sendGesture(back, to: id) }
                                            .buttonStyle(.row).fixedSize()
                                            .disabled(done || !world.inWorld || model.worldSending)
                                    }
                                }
                                .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                            }
                        }
                    }
                }
            }
            if !isYou {
                Text("Others see the same of \(model.name): its name, level, days, medals and counts. Never its mood, your projects, or what it knows.")
                    .caption().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func numberRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            Text(value).font(.bodyStrong).monospacedDigit()
        }
        .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
    }

    /// "Level 9 · 21 days in a row".
    static func levelLine(level: Int, days: Int) -> String {
        "Level \(level.formatted())" + (BoopPane.inARow(days).map { " · " + $0 } ?? "")
    }

    /// "1st", "2nd", "3rd", "4th".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        let suffix = (11...13).contains(tens) ? "th" : ones == 1 ? "st" : ones == 2 ? "nd" : ones == 3 ? "rd" : "th"
        return "\(n.formatted())\(suffix)"
    }

    /// The buttons: Boop, Wave, Heart, and Cheer the ship while it ships; beside them how it went.
    private func actions(_ id: String, name: String, activity: World.Activity, world: Runtime.WorldStatus) -> some View {
        let sent = model.worldSent[id] ?? .init()
        return VStack(alignment: .leading, spacing: Theme.gapSnug) {
            HStack(spacing: Theme.gapSnug) {
                ForEach(Self.gestures(for: activity).filter { $0 != .cheer }, id: \.self) { kind in
                    let done = sent.sent.contains(kind)
                    Button { model.sendGesture(kind, to: id) } label: {
                        Label(done ? "Sent" : kind == .cheer ? "Cheer the ship" : Self.verb(kind),
                              systemImage: done ? "checkmark" : Self.symbol(kind))
                    }
                    .buttonStyle(.row)
                    .fixedSize()
                    .disabled(done || !world.inWorld || model.worldSending)
                }
            }
            if activity == .shipping {
                let done = sent.sent.contains(.cheer)
                Button { model.sendGesture(.cheer, to: id) } label: {
                    Label(done ? "Cheered" : "Cheer the ship", systemImage: done ? "checkmark" : Self.symbol(.cheer))
                }
                .buttonStyle(.rowFilled)
                .fixedSize()
                .disabled(done || !world.inWorld || model.worldSending)
            }
            if let (words, isFailure) = Self.sentWords(sent, name: name, asleep: activity == .asleep, world: world, me: model.name) {
                Text(words).caption()
                    .foregroundStyle(isFailure ? Theme.clayInk : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A gesture's button word.
    static func verb(_ kind: World.GestureKind) -> String {
        switch kind {
        case .boop: "Boop"
        case .wave: "Wave"
        case .heart: "Heart"
        case .cheer: "Cheer"
        }
    }

    /// "You two": what each last sent the other, and the last week you beat them.
    static func youTwo(_ b: World.Profile.Between, them: String, you: String, now: Date = Date()) -> [(words: String, back: World.GestureKind?)] {
        var out: [(String, World.GestureKind?)] = []
        if let sent = b.fromThem, let kind = World.GestureKind(rawValue: sent.kind) {
            let did = switch kind {
            case .boop: "booped \(you)"
            case .wave: "waved at \(you)"
            case .heart: "sent \(you) a heart"
            case .cheer: "cheered your ship"
            }
            out.append(("\(them) \(did) \(ago(sent.at, now: now)).", kind == .cheer ? .heart : kind))
        }
        if let week = b.youBeatThem { out.append(("You beat \(them) \(weeksAgo(week, now: now)).", nil)) }
        return out
    }

    /// "today", "yesterday", "3 days ago".
    static func ago(_ iso: String, now: Date) -> String {
        guard let at = ISO8601DateFormatter().date(from: iso) else { return "lately" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: at), to: Calendar.current.startOfDay(for: now)).day ?? 0
        return days <= 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
    }

    /// "last week", "2 weeks ago", for a week's Monday.
    static func weeksAgo(_ monday: String, now: Date) -> String {
        guard let at = ISO8601DateFormatter().date(from: monday + "T00:00:00Z") else { return "lately" }
        let weeks = Int(now.timeIntervalSince(at) / (7 * 86_400))
        return weeks <= 1 ? "last week" : "\(weeks) weeks ago"
    }

    /// Where it is and its time there: "Asia and Oceania, 16:05 there."
    static func where_(_ region: World.Region?, offset: Int?, now: Date = Date()) -> String? {
        guard let region else { return nil }
        var s = region.name
        if let offset, let zone = TimeZone(secondsFromGMT: offset * 60) {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = zone
            s += ", \(now.formatted(style)) there"
        }
        return s + "."
    }

    /// What a buddy is doing, in the app's words: the wire's idle is resting.
    static func doing(_ activity: World.Activity) -> String {
        activity == .idle ? "resting" : activity.words
    }

    /// Under the buttons: why they can't be pressed, or how the last went,
    /// and whether that's a failure.
    static func sentWords(_ sent: AppModel.WorldSend, name: String, asleep: Bool, world: Runtime.WorldStatus, me: String) -> (String, Bool)? {
        if !world.inWorld { return ("\(me) is still finding its way into the world.", false) }
        if sent.failed != nil { return ("That didn't go through.", true) }
        if sent.sending != nil { return nil }
        let later = asleep ? "\(name) will see it when it wakes." : nil
        if !sent.sent.isEmpty { return (later ?? "\(name) will see it in a moment.", false) }
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
                                if let from = arrival.fromID, let kind = arrival.counts.first?.kind, model.status?.world?.on == true {
                                    let back: World.GestureKind = kind == .cheer ? .heart : kind
                                    let done = model.worldSent[from]?.sent.contains(back) == true
                                    Button(done ? "Sent" : "\(Self.verb(back)) back") { model.sendGesture(back, to: from) }
                                        .buttonStyle(.row).fixedSize()
                                        .disabled(done || model.worldSending)
                                }
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

/// A buddy's medals: a gold, silver and bronze disk, each with its count; none shown at 0.
struct MedalsRow: View {
    let medals: World.Profile.Medals

    var body: some View {
        HStack(spacing: Theme.gapSnug) {
            ForEach([(medals.gold, "#E9BD5A"), (medals.silver, "#CFD5DC"), (medals.bronze, "#D39A6A")].filter { $0.0 > 0 }, id: \.1) { n, hex in
                HStack(spacing: Theme.gapTight) {
                    Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                    Text("\(n)").font(.detailStrong).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Medals: \(medals.gold) gold, \(medals.silver) silver, \(medals.bronze) bronze")
    }
}

extension View {
    /// A face drawn in the buddy's colour (`BuddyColor`), turned as the gel's
    /// material is: near enough for a small face.
    func buddyColor(_ index: Int) -> some View {
        let c = BuddyColor.of(index)
        return hueRotation(.degrees(c.degrees)).saturation(c.saturation).brightness((c.brightness - 1) / 2)
    }
}
