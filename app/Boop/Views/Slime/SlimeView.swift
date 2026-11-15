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
    /// Something needs you: the tile's edge turns amber, as the still
    /// face's does.
    var needsYou = false
    @Environment(\.stillMotion) private var still

    /// Below this many points the board's whole screen leaves the slime a
    /// smudge, so the tile shows the slime alone (the popover's 46 pt one);
    /// onboarding's, all larger, show the whole screen.
    static let zoomBelow: CGFloat = 80
    var zoomed: Bool { min(size, height ?? size) < Self.zoomBelow }

    init(feed: SlimeFeed, snapshot: StateSnapshot, live: Bool, size: CGFloat, height: CGFloat? = nil, needsYou: Bool = false) {
        self.feed = feed
        self.snapshot = snapshot
        self.live = live
        self.size = size
        self.height = height
        self.needsYou = needsYou
    }

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
        .clipShape(TileShape(side: min(size, height ?? size)))
        .overlay(TileEdge(side: min(size, height ?? size), needsYou: needsYou))
        .accessibilityLabel("Boop, \(snapshot.mood), \(snapshot.visual)")
    }
}

/// The face tile's one shape, the slime's and the still face's: corners a
/// little over a quarter of its side, continuous, as the board's glass.
struct TileShape: InsettableShape {
    let side: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: max(0, side * 0.27 - inset), style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
    }
    func inset(by amount: CGFloat) -> TileShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The tile's edge, so the black glass has one on dark paper too: a
/// hairline, amber and heavier while something needs you.
struct TileEdge: View {
    let side: CGFloat
    let needsYou: Bool
    var body: some View {
        TileShape(side: side)
            .strokeBorder(needsYou ? Theme.amberSignal : Theme.hairlineStrong, lineWidth: needsYou ? max(1.5, side * 0.04) : 1)
            .animation(.boopSettle, value: needsYou)
    }
}
