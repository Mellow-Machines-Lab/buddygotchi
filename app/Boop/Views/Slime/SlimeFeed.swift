import AppKit
import BoopKit
import Foundation
import LinkKit
import WebKit

/// The character pack's mirror of the board (characters/CHARACTER.md §9):
/// the board's own firmware in a web page, fed the messages the board gets.
/// A silent mirror: nothing it says comes back, so it can't play a reaction
/// on the board, pick a mood or end a reaction.
@MainActor
final class SlimeFeed: NSObject, WKNavigationDelegate {
    private(set) weak var webView: WKWebView?
    private var ready = false
    private var visible = false
    private var state: StateSnapshot?
    /// A fixed frame for SwiftUI's synchronous snapshot path. WKWebView's
    /// remote layers cannot be captured by NSView.cacheDisplay.
    var stillImage: NSImage?
    var didLoad: (() -> Void)?
    var didFail: ((String) -> Void)?

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
    }

    /// What the board shows, and whether the mirror is on screen.
    func update(_ snapshot: StateSnapshot, visible: Bool) {
        if state != snapshot {
            state = snapshot
            send(Wire.state(snapshot.fields))
        }
        if self.visible != visible {
            self.visible = visible
            call("window.BoopMirror.shown(visible)", ["visible": visible])
        }
    }

    /// A reaction the board got, with the id and play it was sent with; or
    /// one the board played by itself (id 0): push-to-talk's `listening`,
    /// and a tap's poke, which only a finger on the mirror's screen makes.
    func reaction(_ reaction: DeviceReaction, id: Int = 0, play: Wire.Play = .next) {
        if reaction.name == "poked" || reaction.name == "tap_spam" { return poke() }
        send(Wire.do(id: id, name: reaction.name, play: play, ttl: BoopDevice.reactionTTL, args: reaction.args))
    }

    /// A finger on the mirror's screen: it pokes back, as the board does.
    func poke() { call("window.BoopMirror.tap()") }

    private func send(_ line: String) { call("window.BoopMirror.send(line)", ["line": line]) }

    private func call(_ script: String, _ arguments: [String: Any] = [:], on view: WKWebView? = nil) {
        guard let target = view ?? (ready ? webView : nil) else { return }
        target.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result, target === self?.webView { self?.didFail?(error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let state { send(Wire.state(state.fields)) }
        call("window.BoopMirror.shown(visible)", ["visible": visible])
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
