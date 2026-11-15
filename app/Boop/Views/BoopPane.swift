import BoopKit
import SwiftUI

/// The Boop tab: today's ring and the level, the last 7 days' rings, and a
/// peek at what Boop knows, which opens the whole memory. No game words:
/// the ring counts to 100, the level has a bar, and the days together are
/// days.
struct BoopPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            if let status = model.status {
                if let growth = status.growth { today(growth, daysOld: status.daysOld) }
                if !status.week.isEmpty {
                    PaneSection("The last 7 days") { week(status.week) }
                }
                PaneSection("What \(model.name) knows") { knows(status.notes) }
            } else {
                NoteCard("\(model.name) isn't running, so there's nothing to show yet.")
            }
        }
    }

    // MARK: Today

    static let ringSize: CGFloat = 96, ringWidth: CGFloat = 9

    /// Today's ring with its number inside, the level beside it, top-aligned
    /// so "Level N" never moves, and the day's line under both, full width.
    private func today(_ growth: Growth, daysOld: Int?) -> some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .top, spacing: Theme.gutter) {
                Ring(fill: Double(growth.today) / Double(Growth.perDay), width: Self.ringWidth)
                    .frame(width: Self.ringSize, height: Self.ringSize)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(growth.today)").font(.boopDisplay).monospacedDigit()
                            Text("of \(Growth.perDay)").caption()
                        }
                        // The digits' ink sits low in their line: lift it to the ring's middle.
                        .offset(y: -1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Today's ring: \(growth.today) of \(Growth.perDay)")
                VStack(alignment: .leading, spacing: Theme.gapSnug) {
                    Text("Level \(growth.level.formatted())").font(.boopTitle)
                        .padding(.top, Theme.gapSnug)
                    levelBar(growth)
                    if let daysOld { Text(Self.together(daysOld)).font(.body).foregroundStyle(Theme.inkSoft) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(line(growth))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    /// "47 days together", from Boop's age.
    static func together(_ daysOld: Int) -> String {
        switch daysOld {
        case ...0: "Your first day together"
        case 1: "1 day together"
        default: "\(daysOld.formatted()) days together"
        }
    }

    /// One warm line about today's ring.
    private func line(_ growth: Growth) -> String {
        if growth.ringClosed { return "Today's ring is full. Nice work." }
        if growth.today == 0 { return "Nothing yet today. Work with your agents, or give \(model.name) a pet." }
        return "\(growth.today) today. Fill the ring and you're done for the day."
    }

    // MARK: The week

    /// Always seven slots, in a card: the days before Boop was born are
    /// dashed and faint.
    private func week(_ days: [Runtime.Status.DayRing]) -> some View {
        Card {
            HStack(spacing: 0) {
                ForEach(Self.seven(days), id: \.day) { slot in
                    VStack(spacing: Theme.gapTight) {
                        if let ring = slot.ring {
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
