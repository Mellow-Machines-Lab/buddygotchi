import AppKit
import BoopKit
import Foundation
import LinkKit
import WebKit

/// The character pack's mirror of the board (characters/CHARACTER.md §9):
/// the board's own firmware in a web page, fed the messages a board gets.
/// The popover's mirrors the first buddy's board: every message its link
/// sends it, and what it does by itself (`Runtime.onBoardLine`,
/// `onBoardTap`, `onBoardListening`). Onboarding's has no board behind it, so it
/// says what its views show itself, again as often as a link does, and
/// plays its own reactions. A silent mirror: nothing it says comes back,
/// so it can't play a reaction on the board, pick a mood or end a reaction.
@MainActor
final class SlimeFeed: NSObject, WKNavigationDelegate {
    /// It mirrors a board's link (the popover's), not its views' snapshots.
    let mirrorsBoard: Bool
    private(set) weak var webView: WKWebView?
    private var ready = false
    private var visible = false
    /// The latest `state` sent, the page's first message when it loads.
    private var state: String?
    /// With no board behind it, the latest `state` again, as a link's keepalive.
    private var keepalive: Timer?
    /// A fixed frame for SwiftUI's synchronous snapshot path. WKWebView's
    /// remote layers cannot be captured by NSView.cacheDisplay.
    var stillImage: NSImage?
    var didLoad: (() -> Void)?
    var didFail: ((String) -> Void)?

    init(mirrorsBoard: Bool = false) { self.mirrorsBoard = mirrorsBoard }

    /// The character pack's mirror. Nil for a pack with none, which the
    /// popover then draws as its still face.
    static var folder: URL? {
        let folder = CharacterPack.active.directory.appendingPathComponent("mac/mirror")
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) ? folder : nil
    }
    static var document: URL? { folder?.appendingPathComponent("index.html") }

    /// A page to feed. One runs at a time: the one before stops drawing.
    func attach(_ webView: WKWebView) {
        if let old = self.webView, old !== webView { call("window.BoopMirror.shown(false)", on: old) }
        self.webView = webView
        ready = false
        webView.navigationDelegate = self
        guard let folder = Self.folder, let document = Self.document else { return }
        webView.loadFileURL(document, allowingReadAccessTo: folder)
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        call("window.BoopMirror.shown(false)")
        webView.stopLoading()
        webView.navigationDelegate = nil
        self.webView = nil
        ready = false
        keepalive?.invalidate()
        keepalive = nil
    }

    /// A message the board got, as its link sent it.
    func send(_ line: String) {
        if line.hasPrefix(#"{"t":"state""#) { state = line }
        call("window.BoopMirror.send(line)", ["line": line])
    }

    /// What its views show, and whether the mirror is on screen. A board's
    /// mirror shows what the board's lines say instead.
    func update(_ snapshot: StateSnapshot, visible: Bool) {
        if !mirrorsBoard, state != snapshot.jsonLine { send(snapshot.jsonLine) }
        if self.visible != visible {
            self.visible = visible
            call("window.BoopMirror.shown(visible)", ["visible": visible])
        }
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

    /// A `do` no link sent, with no id, since nothing it says comes back.
    private func play(_ reaction: DeviceReaction, _ play: Wire.Play) {
        send(Wire.do(id: 0, name: reaction.name, play: play, ttl: BoopDevice.reactionTTL, args: reaction.args))
    }

    private func call(_ script: String, _ arguments: [String: Any] = [:], on view: WKWebView? = nil) {
        guard let target = view ?? (ready ? webView : nil) else { return }
        target.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result, target === self?.webView { self?.didFail?(error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let state { send(state) }
        call("window.BoopMirror.shown(visible)", ["visible": visible])
        if !mirrorsBoard {
            keepalive?.invalidate()
            keepalive = Timer.scheduledTimer(withTimeInterval: Double(DeviceLink.keepaliveMs) / 1000, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let state = self.state { self.send(state) } }
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
