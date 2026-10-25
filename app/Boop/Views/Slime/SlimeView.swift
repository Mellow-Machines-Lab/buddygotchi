import AppKit
import BoopKit
import SwiftUI

/// A place for the feed's page, which it takes from the view before.
struct SlimeView: NSViewRepresentable {
    let feed: SlimeFeed
    let snapshot: StateSnapshot
    let visible: Bool
    let zoomed: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        feed.place(in: container)
        return container
    }
    func updateNSView(_ container: NSView, context: Context) {
        feed.update(snapshot, visible: visible, zoomed: zoomed, from: container)
    }
    func makeCoordinator() -> SlimeFeed { feed }
    static func dismantleNSView(_ container: NSView, coordinator: SlimeFeed) { coordinator.release(container) }
}

struct SlimeFace: View {
    let feed: SlimeFeed
    let snapshot: StateSnapshot
    let live: Bool
    let size: CGFloat
    /// Taller or shorter than `size`, for a tile that isn't square: a 4:3
    /// one shows the board's whole screen, which a square one crops a little.
    var height: CGFloat?
    @Environment(\.stillMotion) private var still

    /// Below this many points the board's whole screen leaves the slime a
    /// smudge, so the tile shows the slime alone (the popover's 46 pt one);
    /// onboarding's, all larger, show the whole screen.
    static let zoomBelow: CGFloat = 80
    var zoomed: Bool { min(size, height ?? size) < Self.zoomBelow }

    var body: some View {
        Group {
            if still, let image = feed.stillImage {
                // As tall as the tile, as the page draws the board's screen.
                let tall = height ?? size
                Image(nsImage: image).resizable().frame(width: tall * image.size.width / max(image.size.height, 1), height: tall)
            } else {
                SlimeView(feed: feed, snapshot: snapshot, visible: live && !still, zoomed: zoomed)
            }
        }
        .frame(width: size, height: height ?? size)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: min(size, height ?? size) * 0.27))
        .accessibilityLabel("Boop, \(snapshot.mood), \(snapshot.visual)")
    }
}
