import AppKit
import BoopKit
import Foundation
import LinkKit
import WebKit

/// The character pack's mirror of the board (characters/CHARACTER.md §9):
/// the board's own firmware in a web page, fed the messages a board gets.
/// The popover's mirrors the first buddy's board: every message its link
/// sends it, and what it does by itself (`Runtime.onBoardLine`,
/// `onBoardTap`, `onBoardListening`); the link sends it the Mac's `state`,
/// and its keepalive, whether or not a board is connected. Onboarding's has no board behind it, so it
/// says what its views show itself, again as often as a link does, and
/// plays its own reactions. A silent mirror: nothing it says comes back,
/// so it can't play a reaction on the board, pick a mood or end a reaction.
///
/// Each feed keeps one page, its board running, and the view showing the
/// mirror holds it: a new view takes it from the one before, so the slime
/// carries on from act to act in onboarding, with no page to load again.
@MainActor
final class SlimeFeed: NSObject, WKNavigationDelegate {
    /// It mirrors a board's link (the popover's), not its views' snapshots.
    let mirrorsBoard: Bool
    /// The page, made when it's first shown or preloaded.
    private(set) var webView: WKWebView?
    /// The view showing the page now; the only one whose updates count.
    private(set) weak var holder: NSView?
    private var ready = false
    /// The page has drawn the board's first frame, and faded in over the
    /// glass: until then it's clear, so the slime never pops in.
    private var drawn = false
    private var visible = false
    private var zoomed = false
    /// The latest `state` sent, the page's first message when it loads.
    private var state: String?
    /// A board's mirror has had a line from the board's link. Until then
    /// (no runtime yet) it shows its views' snapshot.
    private var heardBoard = false
    /// With no board behind it, the latest `state` again, as a link's keepalive.
    private var keepalive: Timer?
    /// A fixed frame for SwiftUI's synchronous snapshot path. WKWebView's
    /// remote layers cannot be captured by NSView.cacheDisplay.
    var stillImage: NSImage?
    var didLoad: (() -> Void)?
    var didFail: ((String) -> Void)?

    init(mirrorsBoard: Bool = false) { self.mirrorsBoard = mirrorsBoard }

    isolated deinit { keepalive?.invalidate() }

    /// The character pack's mirror. Nil for a pack with none, which the
    /// popover then draws as its still face. The pack doesn't change while
    /// the app runs, so it's looked for once.
    static let folder: URL? = {
        let folder = CharacterPack.active.directory.appendingPathComponent("mac/mirror")
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) ? folder : nil
    }()
    static let document: URL? = folder?.appendingPathComponent("index.html")

    /// No network, navigation, message handlers, storage persistence or audio.
    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    /// Makes the page and starts loading it, before any view shows it, so
    /// the first one shows the slime at once.
    func preload() { _ = page() }

    private func page() -> WKWebView {
        if let webView { return webView }
        let view = Self.makeWebView()
        webView = view
        ready = false
        drawn = false
        view.alphaValue = 0
        view.navigationDelegate = self
        if let folder = Self.folder, let document = Self.document { view.loadFileURL(document, allowingReadAccessTo: folder) }
        return view
    }

    /// `container` shows the page from now on, taken from the view that
    /// showed it before, which is left with its glass until it goes.
    func place(in container: NSView) {
        let view = page()
        holder = container
        guard view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    /// `container` is going. Only the view still showing the page hides
    /// it: one that a newer view took it from has nothing to say.
    func release(_ container: NSView) {
        guard holder === container else { return }
        holder = nil
        show(false)
        webView?.removeFromSuperview()
    }

    /// Stops the page and its board for good.
    func close() {
        keepalive?.invalidate()
        keepalive = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        holder = nil
        ready = false
    }

    /// A message the board got, as its link sent it.
    func send(_ line: String) {
        if mirrorsBoard { heardBoard = true }
        post(line)
    }

    private func post(_ line: String) {
        let isState = line.hasPrefix(#"{"t":"state""#)
        if isState { state = line }
        // The first state powers the board, which draws its frame before
        // the promise settles.
        call(isState && !drawn ? "await window.BoopMirror.send(line)" : "window.BoopMirror.send(line)", ["line": line],
             then: isState && !drawn ? { [weak self] in self?.reveal() } : nil)
    }

    /// The board's first frame is drawn: the page fades in over the glass.
    private func reveal() {
        guard !drawn, let view = webView else { return }
        drawn = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
    }

    /// How long the page takes to fade in once it has drawn.
    static let fadeIn: TimeInterval = 0.25

    /// What `container`'s view shows, whether it's on screen, and whether
    /// it frames the slime alone, for a small tile. A board's mirror shows
    /// what the board's lines say instead, once there are any.
    func update(_ snapshot: StateSnapshot, visible: Bool, zoomed: Bool, from container: NSView) {
        guard holder === container else { return }
        if !mirrorsBoard || !heardBoard, state != snapshot.jsonLine { post(snapshot.jsonLine) }
        if self.zoomed != zoomed {
            self.zoomed = zoomed
            call("window.BoopMirror.zoom(on)", ["on": zoomed])
        }
        show(visible)
    }

    /// Whether the mirror is on screen: it draws only then. The popover
    /// says so as it opens, before its views catch up, so the page draws
    /// where the board is now before it's seen.
    func show(_ on: Bool) {
        guard visible != on else { return }
        visible = on
        call("window.BoopMirror.shown(visible)", ["visible": on])
    }

    /// A tap on the board, which the mirror takes as its own, as the board
    /// did: a finger on its screen, or BOOT (`button`).
    func tap(button: Bool) { call("window.BoopMirror.tap(button)", ["button": button]) }
    /// A click on onboarding's mirror: it pokes back, as the board does.
    func poke() { tap(button: false) }

    /// Push-to-talk on the board's BOOT, which shows `listening` at once by
    /// itself: the mirror plays it as the `do` it is.
    func listening() { play(DeviceReaction(anim: BoopDevice.listening), .now) }
    /// One of onboarding's reactions, as the brain's are sent.
    func reaction(_ reaction: DeviceReaction) { play(reaction, .next) }
    /// One of onboarding's pretend agent's words come forward (a `call`'s
    /// `args`), as the work stream sends one.
    func call(_ args: JSONObject) {
        post(Wire.do(id: 0, name: BoopDevice.call, play: .next, ttl: BoopDevice.callTTL, args: args))
    }

    /// A `do` no link sent, with no id, since nothing it says comes back.
    private func play(_ reaction: DeviceReaction, _ play: Wire.Play) {
        post(Wire.do(id: 0, name: reaction.name, play: play, ttl: BoopDevice.reactionTTL, args: reaction.args))
    }

    private func call(_ script: String, _ arguments: [String: Any] = [:], then: (() -> Void)? = nil) {
        guard ready, let target = webView else { return }
        target.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            guard target === self?.webView else { return }
            switch result {
            case .failure(let error): self?.didFail?(error.localizedDescription)
            case .success: then?()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let state { post(state) }
        call("window.BoopMirror.zoom(on)", ["on": zoomed])
        call("window.BoopMirror.shown(visible)", ["visible": visible])
        if !mirrorsBoard {
            keepalive?.invalidate()
            keepalive = Timer.scheduledTimer(withTimeInterval: Double(DeviceLink.keepaliveMs) / 1000, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let state = self.state { self.post(state) } }
            }
        }
        didLoad?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { didFail?(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { didFail?(error.localizedDescription) }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let initial = action.navigationType == .other && action.request.url?.standardizedFileURL == Self.document?.standardizedFileURL
        decisionHandler(initial ? .allow : .cancel)
    }
}
