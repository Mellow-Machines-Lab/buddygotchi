import AppKit
import BoopKit
import Foundation
import LinkKit
import WebKit

/// Boop facts into the bundled engine. This is a silent mirror; no callback
/// can play a reaction on the device, select a mood, or finish a reaction's handle.
@MainActor
final class SlimeFeed: NSObject, WKNavigationDelegate {
    private(set) weak var webView: WKWebView?
    private var ready = false
    private var visible = false
    private var reduced = false
    private var listening = false
    private var localReaction = 0
    private var state: StateSnapshot?
    /// A fixed frame for SwiftUI's synchronous snapshot path. WKWebView's
    /// remote layers cannot be captured by NSView.cacheDisplay.
    var stillImage: NSImage?
    var didLoad: (() -> Void)?
    var didFail: ((String) -> Void)?

    /// The character pack's mirror (characters/CHARACTER.md §9): Boop's
    /// is slimegen's engine and renderer. Nil for a pack with none, which
    /// the popover then draws as its still face.
    static var folder: URL? {
        let folder = CharacterPack.active.directory.appendingPathComponent("mac/mirror")
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) ? folder : nil
    }
    static var document: URL? { folder?.appendingPathComponent("index.html") }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        ready = false
        webView.navigationDelegate = self
        guard let folder = Self.folder, let document = Self.document else { return }
        webView.loadFileURL(document, allowingReadAccessTo: folder)
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        send(kind: "visibility", value: false)
        webView.stopLoading()
        webView.navigationDelegate = nil
        self.webView = nil
        ready = false
    }

    func update(_ snapshot: StateSnapshot, visible: Bool, reduced: Bool, listening: Bool = false) {
        if state != snapshot { state = snapshot; send(kind: "state", value: Self.object(snapshot.fields)) }
        if self.listening != listening { self.listening = listening; send(kind: "listening", value: listening) }
        if self.visible != visible { self.visible = visible; send(kind: "visibility", value: visible) }
        if self.reduced != reduced { self.reduced = reduced; send(kind: "reduced", value: reduced) }
    }

    /// Reactions already over are never queued for a newly opened popover.
    func reaction(id: Int, _ reaction: DeviceReaction) {
        guard visible else { return }
        localReaction += 1
        let identity = id == 0 ? "local-\(localReaction)" : String(id)
        send(kind: "moment", value: ["id": identity, "name": reaction.name, "args": Self.object(reaction.args)])
    }

    static func object(_ object: JSONObject) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(object.json.utf8))) as? [String: Any] ?? [:]
    }

    private func send(kind: String, value: Any) {
        guard ready, let webView else { return }
        webView.callAsyncJavaScript("window.BoopSlime.feed(message)", arguments: ["message": ["kind": kind, "value": value]],
                                    in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { self?.didFail?(error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let state { send(kind: "state", value: Self.object(state.fields)) }
        send(kind: "reduced", value: reduced)
        send(kind: "listening", value: listening)
        send(kind: "visibility", value: visible)
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
