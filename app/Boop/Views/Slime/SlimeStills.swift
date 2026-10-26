import AppKit
import BoopKit
import SwiftUI
import WebKit

/// Still pictures of the pack's mirror of the board, each a board on a
/// frozen clock in one `state`, zoomed on the slime: for tiles that show a
/// look rather than the board, such as onboarding's legend of moods. One
/// page draws them all, one after another, off screen, and goes; each
/// picture is kept for the app's lifetime.
@MainActor
final class SlimeStills: ObservableObject {
    static let shared = SlimeStills()

    /// By the state's message.
    @Published private(set) var images: [String: NSImage] = [:]
    private var waiting: [StateSnapshot] = []
    private var feed: SlimeFeed?
    private var window: NSWindow?

    /// The tile's size, in points: a picture is drawn at twice that.
    static let side: CGFloat = 46

    func image(_ snapshot: StateSnapshot) -> NSImage? { images[snapshot.jsonLine] }

    /// A picture the snapshot harness drew already.
    func keep(_ image: NSImage, for snapshot: StateSnapshot) { images[snapshot.jsonLine] = image }

    /// Draws `snapshots` that aren't drawn or waiting, for a pack with a mirror.
    func want(_ snapshots: [StateSnapshot]) {
        guard SlimeFeed.folder != nil else { return }
        let lines = Set(images.keys).union(waiting.map(\.jsonLine))
        waiting += snapshots.filter { !lines.contains($0.jsonLine) }
        if feed == nil, !waiting.isEmpty { open() }
    }

    private func open() {
        let size = NSSize(width: Self.side, height: Self.side)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = container
        window.orderBack(nil)
        let feed = SlimeFeed()
        feed.didLoad = { [weak self] in self?.next() }
        feed.didFail = { [weak self] _ in self?.close() }
        feed.place(in: container)
        self.feed = feed
        self.window = window
    }

    private func next() {
        guard let view = feed?.webView, let snapshot = waiting.first else { return close() }
        view.callAsyncJavaScript("window.BoopMirror.zoom(true); return await window.BoopMirror.snapshot(line)",
                                 arguments: ["line": snapshot.jsonLine], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success = result else { return self.close() }
            view.takeSnapshot(with: nil) { image, _ in
                MainActor.assumeIsolated {
                    self.waiting.removeFirst()
                    if let image { self.images[snapshot.jsonLine] = image }
                    self.next()
                }
            }
        }
    }

    /// Done, or the page failed: what's left waits for the next `want`.
    private func close() {
        feed?.close()
        feed = nil
        window?.close()
        window = nil
        waiting = []
    }
}

/// One mood as a still tile: the slime's picture where the pack has a
/// mirror, else the pack's still face.
struct MoodTile: View {
    var mood: String
    var size: CGFloat
    @ObservedObject private var stills = SlimeStills.shared

    static func snapshot(_ mood: String) -> StateSnapshot {
        StateSnapshot(base: "idle", mood: mood, attn: nil, busy: 0, vol: 0)
    }

    var body: some View {
        if SlimeFeed.folder != nil {
            let snapshot = Self.snapshot(mood)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Theme.glass)
                if let image = stills.image(snapshot) {
                    Image(nsImage: image).resizable().interpolation(.high).transition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .animation(.easeOut(duration: SlimeFeed.fadeIn), value: stills.image(snapshot) != nil)
            .onAppear { stills.want([snapshot]) }
            .accessibilityHidden(true)
        } else {
            BoopFace(mood: .idle, design: mood, size: size)
        }
    }
}
