import AppKit
import Foundation
import LinkKit
import WebKit

/// The internal build's simulator: the board's firmware in a window of the
/// app's own (simulator/README.md), Boop's body when there's no board on
/// the desk. Its page (`simulator/web/app.html`, with the simulator's core
/// beside it) is in the app's Resources, which `make bundle INTERNAL=1`
/// puts there, served to the window by a scheme of its own, since a page
/// from a file may not fetch its WebAssembly. Its USB is the app itself
/// (`BoardLink`): what the board says comes in as messages, and what the
/// app sends it goes in by script.
///
/// One window, made when the simulator's link starts and shown again
/// whenever the app is asked to. Closed, the board is gone, as a board
/// unplugged: the link drops until it's shown again.
@MainActor
final class BoardWindow: NSObject, WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate, NSWindowDelegate {
    static let shared = BoardWindow()

    /// The page's folder in the app's Resources, if the build has one.
    nonisolated static let folder: URL? = {
        guard let folder = Bundle.main.url(forResource: "simulator", withExtension: nil),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("app.html").path) else { return nil }
        return folder
    }()
    /// The face the board draws: the one the character pack gives the
    /// AMOLED board, which `make bundle` writes beside the page.
    nonisolated static var face: String {
        folder.flatMap { try? String(contentsOf: $0.appendingPathComponent("face"), encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "gel"
    }
    static let scheme = "boop-board"

    /// The window's title, Boop's name.
    var name: () -> String = { "Boop" }
    /// A window to open beside, onboarding's while it's there.
    var beside: () -> NSWindow? = { nil }
    var log: (String) -> Void = { _ in }

    private var window: NSWindow?
    private var webView: WKWebView?
    /// The link the board is plugged into, while the simulator is Boop's body.
    private var link: BoardLink?
    /// The board is on, its cable in.
    private var on = false

    var isShown: Bool { window?.isVisible == true }

    // MARK: The link

    /// The simulator is Boop's body now: its board is plugged into `link`,
    /// and the window shows.
    func attach(_ link: BoardLink) {
        self.link = link
        if on { link.plugged(true) }
        show()
    }

    /// Boop's body is its board again: the window goes.
    func detach(_ link: BoardLink) {
        guard self.link === link else { return }
        self.link = nil
        close()
    }

    /// The link asked for the board again: it's plugged back in if it's on,
    /// else the window shows, which powers it on.
    func replug(_ link: BoardLink) {
        guard self.link === link else { return }
        if on { link.plugged(true) } else { show() }
    }

    /// A message from the app to the board, which a board that's off never hears.
    func send(_ line: String, from link: BoardLink) {
        guard self.link === link, on, let webView else { return }
        webView.callAsyncJavaScript("window.usb(line)", arguments: ["line": line], in: nil, in: .page) { _ in }
    }

    // MARK: The window

    /// Shows the window, making it and its board if it's gone, in front.
    func show() {
        guard let folder = Self.folder else { return }
        if window == nil { make(folder) }
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
    }

    private func make(_ folder: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // The board's speaker, without a click first.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(self, forURLScheme: Self.scheme)
        config.userContentController.add(self, name: "board")
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 602, height: 634), configuration: config)  // the gel board's, which the page then says
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        webView = view

        // The page starts under the title bar, which is the page's colour.
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = name()
        window.backgroundColor = NSColor(red: 0x15 / 255.0, green: 0x15 / 255.0, blue: 0x15 / 255.0, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Beside onboarding's window the first time, then where it was left.
        if !window.setFrameUsingName(Self.autosave) {
            if let other = beside() {
                window.setFrameTopLeftPoint(NSPoint(x: other.frame.maxX + 16, y: other.frame.maxY))
            } else {
                window.center()
            }
        }
        window.setFrameAutosaveName(Self.autosave)
        self.window = window
        load()
    }

    static let autosave = "BoopBoardWindow"

    private func load() {
        guard let webView, let url = URL(string: "\(Self.scheme)://board/app.html?face=\(Self.face)") else { return }
        webView.load(URLRequest(url: url))
    }

    private func close() {
        window?.close()
    }

    /// Closed, its board goes with it, as a board unplugged.
    func windowWillClose(_ notification: Notification) {
        unplug()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "board")
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
    }

    private func unplug() {
        guard on else { return }
        on = false
        link?.plugged(false)
    }

    // MARK: The page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let line = body["line"] as? String {
            link?.heard(line)
        } else if let power = body["power"] as? Bool {
            // A reset is a power-on with no power-off: the cable comes out
            // and goes in again, so the app greets the board that's there now.
            if on { link?.plugged(false) }
            on = power
            if power { link?.plugged(true) }
        } else if let size = body["size"] as? [Double], size.count == 2, let window {
            let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: size[0], height: size[1]))
            let top = window.frame.maxY
            window.setFrame(NSRect(x: window.frame.minX, y: top - frame.height, width: frame.width, height: frame.height),
                            display: true)
        } else if let text = body["log"] as? String {
            log("board window: \(text)")
        }
    }

    /// WebKit ended the page's process: the board went with it, so it's
    /// loaded again, a new power-on.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        unplug()
        load()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.scheme == Self.scheme ? .allow : .cancel)
    }

    /// The page's files, from its folder and nowhere else.
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let folder = Self.folder, let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let file = folder.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(folder.standardizedFileURL.path + "/"), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let type = switch file.pathExtension {
        case "html": "text/html; charset=utf-8"
        case "js": "text/javascript"
        case "wasm": "application/wasm"
        default: "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type, "Content-Length": String(data.count)])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// The board window's USB, as a transport: what the board says comes in,
/// what the app sends goes to it, and it's up while the board is on and
/// the window open. Made each time the simulator is chosen.
final class BoardLink: Transport, @unchecked Sendable {
    let name = "simulator"
    var trouble: TransportTrouble? { nil }
    private let lock = NSLock()
    private var onLine: (@Sendable (String) -> Void)?
    private var onConnection: (@Sendable (Bool) -> Void)?
    private var up = false

    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            self.onLine = onLine
            self.onConnection = onConnection
        }
        DispatchQueue.main.async { BoardWindow.shared.attach(self) }
    }

    func send(_ line: String) {
        DispatchQueue.main.async { BoardWindow.shared.send(line, from: self) }
    }

    /// Plugs the board in afresh.
    func reconnect() {
        plugged(false)
        DispatchQueue.main.async { BoardWindow.shared.replug(self) }
    }

    func stop() {
        let dropped = lock.withLock { () -> (@Sendable (Bool) -> Void)? in
            defer { onLine = nil; onConnection = nil; up = false }
            return up ? onConnection : nil
        }
        dropped?(false)
        DispatchQueue.main.async { BoardWindow.shared.detach(self) }
    }

    /// A line the board said.
    func heard(_ line: String) { lock.withLock { onLine }?(line) }

    /// The board was plugged in or out: on, or off, a reset, the window closed.
    func plugged(_ on: Bool) {
        let changed = lock.withLock { () -> (@Sendable (Bool) -> Void)? in
            guard up != on else { return nil }
            up = on
            return onConnection
        }
        changed?(on)
    }
}
