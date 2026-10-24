import AppKit
import BoopKit
import SwiftUI
import WebKit

/// No network, navigation, message handlers, storage persistence or audio.
struct SlimeView: NSViewRepresentable {
    let feed: SlimeFeed
    let snapshot: StateSnapshot
    let visible: Bool

    static func webView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        return view
    }
    func makeNSView(context: Context) -> WKWebView {
        let view = Self.webView()
        feed.attach(view)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { feed.update(snapshot, visible: visible) }
    func makeCoordinator() -> SlimeFeed { feed }
    static func dismantleNSView(_ view: WKWebView, coordinator: SlimeFeed) { coordinator.detach(view) }
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

    var body: some View {
        Group {
            if still, let image = feed.stillImage {
                // As tall as the tile, as the page draws the board's screen.
                let tall = height ?? size
                Image(nsImage: image).resizable().frame(width: tall * image.size.width / max(image.size.height, 1), height: tall)
            } else {
                SlimeView(feed: feed, snapshot: snapshot, visible: live && !still)
            }
        }
        .frame(width: size, height: height ?? size)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: min(size, height ?? size) * 0.27))
        .accessibilityLabel("Boop, \(snapshot.mood), \(snapshot.visual)")
    }
}
