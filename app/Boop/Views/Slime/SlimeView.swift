import AppKit
import BoopKit
import SwiftUI
import WebKit

/// No network, navigation, message handlers, storage persistence or audio.
struct SlimeView: NSViewRepresentable {
    let feed: SlimeFeed
    let snapshot: StateSnapshot
    let visible: Bool
    let reduced: Bool
    let listening: Bool

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
    func updateNSView(_ view: WKWebView, context: Context) { feed.update(snapshot, visible: visible, reduced: reduced, listening: listening) }
    func makeCoordinator() -> SlimeFeed { feed }
    static func dismantleNSView(_ view: WKWebView, coordinator: SlimeFeed) { coordinator.detach(view) }
}

struct SlimeFace: View {
    let feed: SlimeFeed
    let snapshot: StateSnapshot
    let live: Bool
    let listening: Bool
    let size: CGFloat
    /// Taller or shorter than `size`, for a tile that isn't square: the
    /// engine's own 4:3 keeps the "needs you" sign whole.
    var height: CGFloat?
    @Environment(\.stillMotion) private var still
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        Group {
            if still, let image = feed.stillImage { Image(nsImage: image).resizable().scaledToFill() }
            else { SlimeView(feed: feed, snapshot: snapshot, visible: live && !still, reduced: reduced, listening: listening) }
        }
        .frame(width: size, height: height ?? size)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: min(size, height ?? size) * 0.27))
        .accessibilityLabel("Boop, \(snapshot.mood), \(snapshot.visual)")
    }
}
