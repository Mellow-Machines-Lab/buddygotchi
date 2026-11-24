import Foundation
import LinkKit

/// The show's picture on its way to the board (linkkit/SPEC.md §3): the
/// core names the show up (`StateSnapshot.ShowField`'s id); its picture is
/// drawn once (`ShowPicture`), sent as a blob, and once the board says it
/// has it the `state`'s `show` names the blob (`b`), so the board draws it.
/// One that hasn't arrived after `retryMs` is sent again, at most `tries`
/// times; a dropped link or a restarted board has lost what it had.
public struct ShowBlobs {
    public static let retryMs: Int64 = 6_000, tries = 3

    /// The show being sent or sent: the core's id, its picture's bytes (nil
    /// when it has none for the board), the blob's id and when it went.
    struct Sending {
        var show: Int
        var bytes: Data?
        var blob: Int?
        var at: Int64
        var tries: Int
        var arrived = false
    }
    var current: Sending?

    public init() {}

    /// The `state`'s fields with the show's blob, sending its picture when
    /// it's new or overdue. `picture` draws the show's picture.
    mutating func fields(_ fields: JSONObject, show: Core.BoardShow?, link: DeviceLink, now: Int64,
                         picture: (Show) -> Data?) -> JSONObject {
        guard let up = show, case .object(var field)? = fields["show"] else {
            current = nil
            return fields
        }
        if current?.show != up.id { current = Sending(show: up.id, bytes: picture(up.show), blob: nil, at: now, tries: 0) }
        guard var sending = current else { return fields }
        if !sending.arrived, sending.bytes != nil, sending.tries < Self.tries,
           sending.blob == nil || now - sending.at >= Self.retryMs, let bytes = sending.bytes,
           let blob = link.blob(bytes, now: now) {
            (sending.blob, sending.at, sending.tries) = (blob, now, sending.tries + 1)
        }
        current = sending
        guard sending.arrived, let blob = sending.blob else { return fields }
        var out = fields
        field["b"] = .int(blob)
        out["show"] = .object(field)
        return out
    }

    /// Whether the picture is due to go (again): not there yet, not sent, or
    /// sent `retryMs` ago, tries left.
    func due(at now: Int64) -> Bool {
        guard let c = current, !c.arrived, c.bytes != nil, c.tries < Self.tries else { return false }
        return c.blob == nil || now - c.at >= Self.retryMs
    }

    /// The board has blob `id`: true when it's the show's, so its `state`
    /// should go again.
    mutating func arrived(_ id: Int) -> Bool {
        guard current?.blob == id, current?.arrived == false else { return false }
        current?.arrived = true
        return true
    }

    /// The link dropped, or the board restarted: what it had is gone.
    mutating func forget() {
        guard current != nil else { return }
        current?.arrived = false
        current?.blob = nil
        current?.tries = 0
    }
}
