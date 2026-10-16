import BoopKit
import SwiftUI

/// A bug report's note, inside the popover: the report is already saved,
/// so the moment is kept however long the note takes.
struct ReportPane: View {
    @ObservedObject var model: AppModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title row, as Settings has it. Back keeps the report, with no note.
            HStack(spacing: Theme.gapTight) {
                Button { model.finishReport(withNote: false) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.quiet)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
                Text("Bug report").font(.boop(16))
                Spacer()
            }
            .padding(.horizontal, Theme.gutter - 8)
            .padding(.top, Theme.gutter - 4)
            .padding(.bottom, Theme.gap)
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(saved)
                    .font(.system(size: 12))
                    .foregroundStyle(model.report?.failed == true ? Theme.clayInk : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("What did \(model.name) do that looked wrong, or what's missing?",
                          text: Binding(get: { model.report?.note ?? "" }, set: { model.report?.note = $0 }),
                          axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(4...8)
                    .padding(10)
                    .fieldBox(Theme.raised, radius: 10, focus: $noteFocused)
                    .accessibilityLabel("Note")
                HStack {
                    Text("Save copies it all for an agent.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Button("Save") { model.finishReport(withNote: true) }
                        .buttonStyle(.prominent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.report?.dir == nil)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, Theme.gapLoose)
        }
        .onAppear { noteFocused = true }
    }

    private var saved: String {
        guard let report = model.report else { return "" }
        if report.failed { return "\(model.name) couldn't save the report. boop.log says why." }
        if report.dir == nil { return "Saving what \(model.name) is doing now…" }
        return "Saved what \(model.name) is doing now and did this launch. Say what you saw, or what you expected."
    }
}
