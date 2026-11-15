import AppKit
import BoopKit
import SwiftUI

/// The popover. One 420 pt column on warm paper; the overview's three tabs
/// (Now, Boop and World), Settings and What Boop knows open inside it.
/// Setup is onboarding's, in its own window.
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
        // The height left under a pane's title row, and over the footer.
        let paneHeight = (maxHeight ?? min(limit, 640)) - 96
        return VStack(spacing: 0) {
            // Stacked, not in a column: while one pane fades into the
            // other, the column would hold both, and the popover grow to
            // their sum for a moment.
            ZStack(alignment: .top) {
                switch model.pane {
                case .overview: OverviewPane(model: model, maxHeight: limit - 44)
                case .settings: SettingsPane(model: model, maxHeight: paneHeight)
                case .memory: MemoryPane(model: model, maxHeight: paneHeight)
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
        // Esc goes back from another pane first, as its chevron does.
        .onExitCommand { if model.pane != .overview { model.pane = .overview } else { onClose() } }
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
                    // A bug report, from anywhere on the Overview: Settings
                    // has its button, and the "stopped unexpectedly" notice.
                    Button("Save a bug report") { model.saveReport() }
                        .keyboardShortcut("b", modifiers: .command)
                        .disabled(model.status == nil)  // Boop isn't running (or not yet)
                        .opacity(0).frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                } else if model.pane == .settings {
                    // The versions, where Settings would be.
                    Text("Boop \(BoopVersion.current)" + (model.status?.device.map { " · firmware \($0.fw)" } ?? ""))
                        .caption()
                        .padding(.leading, Theme.gapSnug)
                        .textSelection(.enabled)
                }
                Spacer()
                // What Boop knows, from anywhere in the popover.
                Button("What \(model.name) knows") { model.pane = .memory }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .opacity(0).frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .font(.body)
            .buttonStyle(.quiet)
            // The quiet buttons' own 8 pt inset puts their words on the gutter.
            .padding(.horizontal, Theme.gap)
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
    /// Where the content ends, in the scroll view's own space.
    @ViewState private var bottom: CGFloat = 0
    private static var space: String { "fitted-scroll" }

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
                // A pane that fits doesn't scroll: with scroll bars always
                // shown (a mouse, or System Settings), a scroll view takes
                // their width from its content, which then wraps taller than
                // its measure and is cut off at the bottom behind a bar.
                ViewThatFits(in: .vertical) {
                    content.fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        content.background(GeometryReader { g in
                            Color.clear.preference(key: ContentBottom.self, value: g.frame(in: .named(Self.space)).maxY)
                        })
                    }
                    .coordinateSpace(name: Self.space)
                    .scrollBounceBehavior(.basedOnSize)
                    // Scroll bars over the content, never beside it: with a
                    // mouse's bars, which take their width from the content,
                    // none, so the cards line up with the header; the fade
                    // says there's more.
                    .scrollIndicators(NSScroller.preferredScrollerStyle == .legacy ? .never : .automatic)
                    .onPreferenceChange(ContentBottom.self) { bottom = $0 }
                    .overlay(alignment: .bottom) {
                        GeometryReader { g in
                            // While more is below: a fade into the footer,
                            // so the last row isn't cut through its words.
                            LinearGradient(colors: [Theme.paper.opacity(0), Theme.paper], startPoint: .top, endPoint: .bottom)
                                .frame(height: Theme.gutter)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .opacity(bottom > g.size.height + 1 ? 1 : 0)
                                .animation(.boopSettle, value: bottom > g.size.height + 1)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
    }
}

/// Where a scroll view's content ends, so it knows whether more is below.
private struct ContentBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
