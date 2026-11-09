import BoopKit
import SwiftUI

/// The Boop tab: today's ring and the level, the last 7 days' rings, and a
/// peek at what Boop knows, which opens the whole memory.
struct BoopPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSection) {
            if let status = model.status {
                if let growth = status.growth { today(growth) }
                if !status.week.isEmpty {
                    PaneSection("The last 7 days") { week(status.week) }
                }
                PaneSection("What \(model.name) knows") { knows(status.notes) }
            } else {
                Card {
                    Text("\(model.name) isn't running, so there's nothing to show yet.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Today

    /// Today's ring, its number in the middle, and beside it the level, the
    /// XP of every day together, how far the next level is, and a line.
    private func today(_ growth: Growth) -> some View {
        HStack(alignment: .center, spacing: Theme.gapLoose) {
            Ring(fill: Double(growth.today) / Double(Growth.perDay), full: growth.ringClosed, width: 9)
                .frame(width: 96, height: 96)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(growth.today)").font(.boop(28, .bold)).monospacedDigit()
                        Text("today").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Level \(growth.level)").font(.boop(18, .bold))
                Text("\(growth.xp.formatted()) XP together").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                Text("\(growth.toNextLevel) to level \(growth.level + 1)").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                Text(line(growth))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// One warm line about today's ring.
    private func line(_ growth: Growth) -> String {
        if growth.ringClosed { return "Today's ring is full. Nice work." }
        if growth.today == 0 { return "Nothing yet today. Work with your agents, or give \(model.name) a pet." }
        return "\(growth.today) today. Fill the ring and you're done for the day."
    }

    // MARK: The week

    private func week(_ days: [Runtime.Status.DayRing]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Ring(fill: Double(day.xp) / Double(Growth.perDay), full: day.xp >= Growth.perDay, width: 4)
                        .frame(width: 26, height: 26)
                    Text(day.name).font(.system(size: 10, weight: day.name == "Today" ? .semibold : .regular))
                        .foregroundStyle(day.name == "Today" ? Theme.ink : Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.name): \(day.xp >= Growth.perDay ? "full" : "\(day.xp)")")
            }
        }
    }

    // MARK: What Boop knows

    /// A few of the written memory's notes, and the way to all of them.
    private func knows(_ notes: [WrittenMemory.Note]) -> some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            if notes.isEmpty {
                Card {
                    Text("\(model.name) is still getting to know you. What it learns shows here after it dreams.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(notes.prefix(Self.peek), id: \.id) { note in
                Card(padding: 10) {
                    Text(note.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { model.pane = .memory } label: {
                Text("See everything \(model.name) knows ›").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.sageInk)
            .padding(.leading, 2)
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    /// How many notes the peek shows.
    static let peek = 3
}

/// A day's ring: a track, and the day's share of it from the top,
/// clockwise; full, it turns green.
struct Ring: View {
    /// 0 to 1.
    let fill: Double
    var full = false
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Theme.well, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(1, fill)))
                .stroke(full ? Theme.sage : Theme.blush, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
    }
}
