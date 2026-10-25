import AppKit
import BoopKit
import Foundation
import WebKit

/// The pack's mirror of the board in a real WKWebView: a board on a frozen
/// clock in the snapshot's state, drawn as a scenario's shot draws it, which
/// must say it shows that state. The bounded wait belongs only to this
/// command, never the runtime.
@MainActor
enum SlimeSnapshots {
    static let timeout: TimeInterval = 15
    /// The board's own screen, so a still fits any tile as the live page does.
    static let panel = NSSize(width: 502, height: 410)

    /// `zoomed`, the slime alone, as a small tile shows it.
    static func image(_ snapshot: StateSnapshot, to output: URL, size: NSSize = panel, zoomed: Bool = false) throws -> NSImage {
        let feed = SlimeFeed(), container = NSView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFront(nil)
        defer { feed.close(); window.close() }
        var image: NSImage?, failure: String?
        feed.didFail = { failure = $0 }
        feed.didLoad = {
            guard let view = feed.webView else { return }
            view.callAsyncJavaScript("window.BoopMirror.zoom(zoomed); return await window.BoopMirror.snapshot(line)",
                                     arguments: ["line": snapshot.jsonLine, "zoomed": zoomed], in: nil, in: .page) { result in
                switch result {
                case .failure(let error): failure = error.localizedDescription
                case .success(let raw):
                    guard let said = raw as? [String: Any], shows(snapshot, said) else {
                        failure = "the mirror's board doesn't show \(snapshot.jsonLine): it says \(raw)"; return
                    }
                    view.takeSnapshot(with: nil) { result, error in
                        if let error { failure = error.localizedDescription }
                        image = result
                    }
                }
            }
        }
        feed.place(in: container)
        let deadline = Date().addingTimeInterval(timeout)
        while image == nil, failure == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard let image, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SlimeSnapshots", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: failure ?? "WebKit did not render within \(timeout) seconds"])
        }
        try png.write(to: output)
        print("\(output.lastPathComponent) \(bitmap.pixelsWide)×\(bitmap.pixelsHigh), the mirror's board in WebKit")
        return image
    }

    /// Whether the board's dbg.state says it shows the snapshot: its base,
    /// act and mood (a mood it doesn't know reads as its startup mood), and
    /// needs you exactly when the snapshot does.
    static func shows(_ snapshot: StateSnapshot, _ state: [String: Any]) -> Bool {
        state["base"] as? String == snapshot.base && state["act"] as? String == snapshot.act
            && state["mood"] as? String == snapshot.mood
            && state["screen"] as? String == (snapshot.attn == nil ? "face" : "needs_you")
    }
}
