import BoopKit
import SwiftUI

/// The Boop tab, your buddy's profile (plan/xp-league.md §4): its level
/// and days in a row, how it feels and why, today's ring and what filled it,
/// the last 7 days' rings, and a peek at what Boop knows, which opens the
/// whole memory.
struct BoopPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            if let status = model.status {
                if let growth = status.growth { who(growth, daysInARow: status.daysInARow) }
                ReasonLines(feed: model.slime, name: model.name, mood: status.snapshot.mood, wish: status.wishing,
                            why: status.moodReason?.cause, doing: status.doingReason?.cause)
                if let growth = status.growth {
                    PaneSection("Today") { today(growth, by: status.todayBy) }
                }
                if !status.week.isEmpty {
                    PaneSection("The last 7 days") { week(status.week) }
                }
                PaneSection("What \(model.name) knows about you") { knows(status.notes) }
            } else {
                NoteCard("\(model.name) isn't running, so there's nothing to show yet.")
            }
        }
    }

    // MARK: Who

    /// The level, the days in a row, and the bar to the next level.
    private func who(_ growth: Growth, daysInARow: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Text("Level \(growth.level.formatted())").font(.boopTitle)
            if let days = Self.inARow(daysInARow) {
                Text(days).font(.body).foregroundStyle(Theme.inkSoft)
            }
            levelBar(growth)
        }
    }

    /// "12 days in a row", or nil before the second.
    static func inARow(_ n: Int) -> String? { n > 1 ? "\(n.formatted()) days in a row" : nil }

    // MARK: Today

    static let ringSize: CGFloat = 88, ringWidth: CGFloat = 9

    /// Today's ring, its XP inside, in two tints, the agents' work and your
    /// time with Boop; beside it what filled it; under both, one line.
    private func today(_ growth: Growth, by: [Growth.Source: GrowthStore.Earned]) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .top, spacing: Theme.gutter) {
                TwoTintRing(work: growth.work, care: growth.care, width: Self.ringWidth)
                    .frame(width: Self.ringSize, height: Self.ringSize)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(growth.today)").font(.boopDisplay).monospacedDigit()
                            Text("XP").caption()
                        }
                        .offset(y: -1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Today: \(growth.today) XP of the ring's \(Growth.perDay)")
                let rows = Self.rows(by, name: model.name)
                if !rows.isEmpty {
                    Card(padding: Card<EmptyView>.rows) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                                if i > 0 { Hairline().padding(.horizontal, Theme.gap) }
                                HStack(spacing: Theme.gapSnug) {
                                    Circle().fill(r.care ? Theme.care : Theme.ring).frame(width: 7, height: 7)
                                    Text(r.words).font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(r.xp)").font(.bodyStrong).monospacedDigit()
                                }
                                .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
                            }
                        }
                    }
                }
            }
            Text(Self.line(growth, name: model.name))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What filled today's ring, a row a source that earned: its words and its XP.
    static func rows(_ by: [Growth.Source: GrowthStore.Earned], name: String) -> [(words: String, xp: Int, care: Bool)] {
        Growth.Source.allCases.compactMap { source in
            guard let e = by[source], e.xp > 0 else { return nil }
            let words: String
            switch source {
            case .turns: words = e.n == 1 ? "1 turn finished" : "\(e.n) turns finished"
            case .ships: words = e.n == 1 ? "1 ship" : "\(e.n) ships"
            case .fixes: words = e.n == 1 ? "Tests fixed once" : "Tests fixed \(e.n) times"
            case .care: words = "Time with \(name)"
            }
            return (words, e.xp, source == .care)
        }
    }

    /// One warm line about today's ring.
    static func line(_ growth: Growth, name: String) -> String {
        if growth.ringClosed { return "Today's ring is full. Nice work." }
        if growth.today == 0 { return "Nothing yet today. Work with your agents, or give \(name) a pet." }
        return "\(Growth.perDay - growth.today) to go. A few more turns will do it, or go and say hi to \(name)."
    }

    /// A thin bar to the next level, and how far it still is.
    private func levelBar(_ growth: Growth) -> some View {
        let done = Double(Growth.perLevel - growth.toNextLevel) / Double(Growth.perLevel)
        return HStack(spacing: Theme.gapSnug) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairlineStrong)
                    Capsule().fill(Theme.ring).frame(width: geo.size.width * done)
                }
            }
            .frame(height: 4)
            Text("\(growth.toNextLevel) to go").font(.body).foregroundStyle(Theme.inkSoft).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(growth.toNextLevel) to level \(growth.level + 1)")
    }

    // MARK: The week

    /// Always seven slots, in a card: the days before Boop was born are
    /// dashed and faint.
    private func week(_ days: [Runtime.Status.DayRing]) -> some View {
        Card {
            HStack(spacing: 0) {
                ForEach(Self.seven(days), id: \.day) { slot in
                    VStack(spacing: Theme.gapTight) {
                        if let ring = slot.ring, ring.xp == 0 {
                            // A day with nothing: a dotted hollow ring, never a red one.
                            Circle().strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 2, dash: [1.5, 3]))
                                .frame(width: 28, height: 28)
                        } else if let ring = slot.ring {
                            Ring(fill: Double(ring.xp) / Double(Growth.perDay), width: 3)
                                .overlay {
                                    if ring.xp >= Growth.perDay {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Theme.sageSignal)
                                    }
                                }
                                .frame(width: 28, height: 28)
                        } else {
                            Circle().strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                                .frame(width: 28, height: 28)
                        }
                        Text(slot.name).font(slot.ring?.isToday == true ? .chip.weight(.semibold) : .chip)
                            .foregroundStyle(slot.ring?.isToday == true ? Theme.ink : Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(slot.ring.map { "\(slot.name): \($0.xp >= Growth.perDay ? "full" : "\($0.xp)")" }
                        ?? "\(slot.name): before \(model.name)")
                }
            }
        }
    }

    /// One of the week's seven slots: a day's ring, or a day before the first.
    struct Slot {
        var day: String
        var name: String
        var ring: Runtime.Status.DayRing?
    }

    /// The last seven days, oldest first: the rings there are, after a
    /// dashed slot for each day before the first ring.
    static func seven(_ days: [Runtime.Status.DayRing]) -> [Slot] {
        let rings = Array(days.suffix(7))
        let missing = 7 - rings.count
        guard missing > 0, let first = rings.first, let start = dayFormat.date(from: first.day) else {
            return rings.map { Slot(day: $0.day, name: $0.name, ring: $0) }
        }
        let before = (1...missing).reversed().map { back -> Slot in
            let date = utc.date(byAdding: .day, value: -back, to: start) ?? start
            let day = dayFormat.string(from: date)
            return Slot(day: day, name: weekdayFormat.string(from: date), ring: nil)
        }
        return before + rings.map { Slot(day: $0.day, name: $0.name, ring: $0) }
    }

    private static let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private static let dayFormat = {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormat = {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    // MARK: What Boop knows

    /// A few of the written memory's notes, plain lines in one card, and
    /// the way to all of them as its last row.
    private func knows(_ notes: [WrittenMemory.Note]) -> some View {
        Card(padding: Card<EmptyView>.rows) {
            VStack(alignment: .leading, spacing: 0) {
                if notes.isEmpty {
                    row(Text("\(model.name) is still getting to know you. What it learns shows here after it dreams.")
                        .foregroundStyle(Theme.inkSoft))
                    Hairline().padding(.horizontal, Theme.gap)
                }
                ForEach(notes.prefix(Self.peek), id: \.id) { note in
                    row(Text(note.text))
                    Hairline().padding(.horizontal, Theme.gap)
                }
                Button { model.pane = .memory } label: { Text("See everything ›") }
                    .buttonStyle(.wordLink)
                    .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapTight)
                    .help("See everything \(model.name) knows (⇧⌘M)")
            }
        }
    }

    private func row(_ text: Text) -> some View {
        text.font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gap).padding(.vertical, Theme.gapSnug)
    }

    /// How many notes the peek shows.
    static let peek = 3
}

/// A day's ring: a track, and the day's share of it from the top,
/// clockwise: blue while it fills, sage when full. The arc starts and ends
/// half a round cap in, so a cap never pokes back past the top.
struct Ring: View {
    /// 0 to 1.
    let fill: Double
    let width: CGFloat
    var full: Bool { fill >= 1 }

    var body: some View {
        GeometryReader { geo in
            let radius = max(1, (min(geo.size.width, geo.size.height) - width) / 2)
            // Half the cap's width, as a share of the circle.
            let cap = Double(width / 2) / Double(2 * .pi * radius)
            let shown = max(0, min(1, fill))
            ZStack {
                Circle().stroke(Theme.hairlineStrong, lineWidth: width)
                if full {
                    Circle().stroke(Theme.sageSignal, lineWidth: width)
                } else if shown > 0 {
                    Circle()
                        .trim(from: cap, to: cap + shown * (1 - 2 * cap))
                        .stroke(Theme.ring, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(width / 2)
        }
    }
}

/// Today's ring in two tints: the agents' work in blue from the top, then
/// your time with Boop in pink; sage once it's full.
struct TwoTintRing: View {
    let work: Int, care: Int
    let width: CGFloat

    var body: some View {
        GeometryReader { geo in
            let radius = max(1, (min(geo.size.width, geo.size.height) - width) / 2)
            let cap = Double(width / 2) / Double(2 * .pi * radius)
            let w = min(1, Double(work) / Double(Growth.perDay))
            let c = min(1 - w, Double(care) / Double(Growth.perDay))
            ZStack {
                Circle().stroke(Theme.hairlineStrong, lineWidth: width)
                if w + c >= 1 {
                    Circle().stroke(Theme.sageSignal, lineWidth: width)
                } else {
                    if w > 0 {
                        Circle().trim(from: cap, to: cap + w * (1 - 2 * cap))
                            .stroke(Theme.ring, style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    if c > 0 {
                        Circle().trim(from: cap + w, to: cap + (w + c) * (1 - 2 * cap))
                            .stroke(Theme.care, style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .padding(width / 2)
        }
    }
}
