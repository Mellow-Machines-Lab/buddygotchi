import BoopKit
import SwiftUI

/// What Boop knows, inside the popover: the written memory as it is, one
/// card for its notes with a heading for each section that has any, and
/// Recently in a card of its own. Each note has a pin, which keeps it from
/// aging and from the dream's edits, and Forget, which says "Forgotten.
/// Undo" in the note's place for a few seconds before it forgets it for
/// good. It reads what `Runtime.Status` read through the memory store, so
/// it follows a dream's write as the status does. The Boop tab's peek
/// opens it.
struct MemoryPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat
    @ObservedObject private var forgets = PendingForgets.shared

    /// The room the caption under the scroll takes from it.
    private static let captionRoom: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("What \(model.name) knows") { model.pane = .overview }
            FittedScroll(maxHeight: maxHeight - (model.status != nil ? Self.captionRoom : 0)) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gap)
            }
            // Pinned at the pane's foot, over the popover's footer, and only
            // while there's a memory it's true of.
            if model.status != nil {
                Text("Written on this Mac as \(model.name) dreams. Its notes go to the brain with each request, and nowhere else.")
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter + Theme.hair)
                    .padding(.top, Theme.gapTight)
                    .padding(.bottom, Theme.gap)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let status = model.status {
            let notes = status.notes.filter { !forgets.gone.contains($0.id) }
            if notes.isEmpty, status.recently.isEmpty {
                NoteCard("\(model.name) is still getting to know you. What it learns shows here after it dreams.")
            } else {
                if !notes.isEmpty { noteCard(notes) }
                if !status.recently.isEmpty {
                    PaneSection("Recently") { days(status.recently) }
                }
            }
        } else {
            Card {
                Label("\(model.name) isn't running, so its memory can't be read now.", systemImage: "exclamationmark.triangle")
                    .font(.body).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One card for every section with notes: its heading inside, its
    /// notes pinned first, a hairline between sections.
    private func noteCard(_ notes: [WrittenMemory.Note]) -> some View {
        let sections = WrittenMemory.Section.allCases.filter { section in notes.contains { $0.section == section } }
        return Card(padding: Card<EmptyView>.rows) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element) { i, section in
                    if i > 0 { Hairline() }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(section.heading.replacingOccurrences(of: "Boop", with: model.name))
                            .padding(.top, Theme.gap).padding(.bottom, Theme.gapTight)
                        ForEach(Self.pinnedFirst(notes.filter { $0.section == section }), id: \.id) { note in
                            row(note)
                        }
                    }
                    .padding(.bottom, Theme.gapTight)
                }
            }
        }
    }

    /// A section's notes, the pinned ones first, each kind in its order.
    static func pinnedFirst(_ notes: [WrittenMemory.Note]) -> [WrittenMemory.Note] {
        notes.filter(\.pinned) + notes.filter { !$0.pinned }
    }

    @ViewBuilder private func row(_ note: WrittenMemory.Note) -> some View {
        if forgets.pending.contains(note.id) {
            HStack(spacing: Theme.gapSnug) {
                Text("Forgotten.").font(.body).foregroundStyle(Theme.inkSoft)
                Button("Undo") { forgets.undo(note.id) }
                    .buttonStyle(.wordLink)
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.gap).padding(.trailing, Theme.gapTight)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(note.text).font(.body).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, Theme.gapTight)
                Spacer(minLength: Theme.gapTight)
                Button { model.runtime?.pinNote(note.id, !note.pinned) } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                        // A pinned pin in ink; the style's soft ink for the rest.
                        .foregroundStyle(note.pinned ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.foreground))
                }
                .buttonStyle(.quietIcon)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .help(note.pinned ? "Let it age as the others do" : "Keep it for good, as it is")
                .accessibilityLabel(note.pinned ? "Unpin" : "Pin")
                Button { forgets.forget(note.id, runtime: model.runtime) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.quietIcon)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .help("Forget it")
                .accessibilityLabel("Forget")
            }
            // The icons' ink lines up with the card's padding.
            .padding(.leading, Theme.gap).padding(.trailing, Theme.gapTight)
        }
    }

    private func days(_ lines: [Runtime.Status.DayLine]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                ForEach(lines) { entry in
                    DayRow(entry: entry, selectable: true)
                }
            }
        }
    }
}

/// The notes forgotten from the pane that can still be undone: each waits
/// a few seconds, then the runtime forgets it for good. Shared, as
/// `OpenDetails` is, because FittedScroll lays the pane out more than once
/// and each copy must show the same rows. A forget still waiting when the
/// app quits is not made: the note stays.
@MainActor
final class PendingForgets: ObservableObject {
    static let shared = PendingForgets()
    /// How long "Forgotten. Undo" stays before the forget is made.
    static let wait: Duration = .seconds(5)

    /// Forgotten, and still to be undone.
    @Published private(set) var pending: Set<Int> = []
    /// Forgotten for good, and hidden until the status no longer has them.
    @Published private(set) var gone: Set<Int> = []
    private var timers: [Int: Task<Void, Never>] = [:]

    func forget(_ id: Int, runtime: Runtime?) {
        pending.insert(id)
        timers[id]?.cancel()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.wait)
            guard let self, !Task.isCancelled, self.pending.contains(id) else { return }
            self.pending.remove(id)
            self.gone.insert(id)
            self.timers[id] = nil
            runtime?.forgetNote(id)
        }
    }

    func undo(_ id: Int) {
        timers.removeValue(forKey: id)?.cancel()
        pending.remove(id)
    }

    /// Shows `id` as forgotten and waiting, with no timer, for a snapshot.
    func show(_ id: Int) { pending.insert(id) }
    /// Forgets every pending forget, made or not, for the next snapshot.
    func reset() {
        timers.values.forEach { $0.cancel() }
        (timers, pending, gone) = ([:], [], [])
    }
}
