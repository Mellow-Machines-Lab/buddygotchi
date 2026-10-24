import AppKit
import BoopKit
import SwiftUI

/// The popover. One 360 pt column on warm paper; Overview and Settings
/// open inside it. Setup is onboarding's, in its own window.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void = {}
    /// The tallest the column grows before it scrolls. The snapshot harness
    /// raises it to capture whole panes.
    var maxHeight: CGFloat? = nil
    @Environment(\.stillMotion) private var still

    private var limit: CGFloat {
        maxHeight ?? min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.pane {
                case .overview: OverviewPane(model: model, maxHeight: limit - 44)
                case .settings: SettingsPane(model: model, maxHeight: (maxHeight ?? min(limit, 640)) - 96)
                }
            }
            .transition(.opacity)
            footer
        }
        .frame(width: Theme.width)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .animation(.boopSettle, value: model.pane)
        // Closed, it's out of sight but not gone: nothing loops, for nobody.
        .environment(\.stillMotion, still || !model.shown)
        .onExitCommand(perform: onClose)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                if model.pane == .overview {
                    Button {
                        model.pane = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    Button {
                        model.saveReport()
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(model.status == nil)  // Boop isn't running (or not yet)
                    .help("Save a bug report: what Boop saw and did this launch, to hand to an agent")
                    .accessibilityLabel("Save a bug report")
                } else if model.pane == .settings {
                    // The versions, where Settings would be.
                    Text("Boop \(BoopVersion.current)" + (model.status?.device.map { " · firmware \($0.fw)" } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .padding(.leading, 8)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .font(.system(size: 12))
            .buttonStyle(.quiet)
            .padding(.horizontal, Theme.gutter - 8)
            .padding(.vertical, Theme.gapSnug)
        }
    }
}

/// A scroll view as tall as its content, up to `maxHeight`, so a short pane
/// makes a short popover and a long one scrolls. A hidden, disabled copy of
/// the content sets the height in the same layout pass, so the popover opens
/// at its final size instead of growing into it.
struct FittedScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .disabled(true)
            .accessibilityHidden(true)
            // Accept less than the measuring copy's ideal height when a
            // pane's header needs room; only the visible overlay scrolls.
            .frame(minHeight: 0, maxHeight: maxHeight, alignment: .top)
            .overlay(alignment: .top) {
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
            }
    }
}
