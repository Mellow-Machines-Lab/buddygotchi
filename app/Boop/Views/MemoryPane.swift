import BoopKit
import SwiftUI

/// What Boop knows, inside the popover: the written memory as it is, a
/// section each, each note with a pin, which keeps it from aging and from
/// the dream's edits, and a cross, which forgets it for good. It reads
/// what `Runtime.Status` read through the memory store, so it follows a
/// dream's write as the status does. The Boop tab's peek opens it.
struct MemoryPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("What \(model.name) knows") { model.pane = .overview }
            FittedScroll(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    content
                    Text("Written on this Mac as \(model.name) dreams. Its notes go to the brain with each request, and nowhere else.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 2)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gapLoose)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let status = model.status {
            if status.notes.isEmpty, status.recently.isEmpty {
                Card {
                    Text("\(model.name) is still getting to know you. What it learns shows here after it dreams.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(WrittenMemory.Section.allCases, id: \.self) { section in
                    PaneSection(section.heading.replacingOccurrences(of: "Boop", with: model.name)) {
                        notes(status.notes.filter { $0.section == section })
                    }
                }
                PaneSection("Recently") { days(status.recently) }
            }
        } else {
            NoteCard("\(model.name) isn't running, so its memory can't be read now.")
        }
    }

    private func notes(_ notes: [WrittenMemory.Note]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                if notes.isEmpty { nothingYet }
                ForEach(notes, id: \.id) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(note.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { model.runtime?.pinNote(note.id, !note.pinned) } label: {
                            Image(systemName: note.pinned ? "pin.fill" : "pin").font(.system(size: 10))
                        }
                        .buttonStyle(.quiet)
                        .help(note.pinned ? "Let it age as the others do" : "Keep it for good, as it is")
                        Button { model.runtime?.forgetNote(note.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 10))
                        }
                        .buttonStyle(.quiet)
                        .help("Forget it")
                    }
                }
            }
        }
    }

    private func days(_ lines: [Runtime.Status.DayLine]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.gapSnug) {
                if lines.isEmpty { nothingYet }
                ForEach(lines) { entry in
                    DayRow(entry: entry, selectable: true)
                }
            }
        }
    }

    private var nothingYet: some View {
        Text("Nothing yet.").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
    }
}
