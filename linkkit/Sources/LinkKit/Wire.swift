import Foundation

/// The device's `hello` (SPEC.md §3): who it is and what it plays.
public struct Hello: Equatable, Sendable {
    /// The protocol version; nil when missing or not an integer. The kit
    /// speaks 1 (SPEC.md §6).
    public var kit: Int?
    /// Which kind of device this is. A host drives only the app it was
    /// written for.
    public var app: String
    /// The device's permanent id: `lamp-54fe`.
    public var id: String
    /// The firmware version.
    public var fw: String
    /// The `do` names it plays.
    public var does: [String]
    /// Picked at random each time the device powers on (8 hex digits), so
    /// a new one means it restarted; nil when it gives none.
    public var boot: String?
    /// Every other field, in the message's order: the app's own.
    public var fields: JSONObject

    public init(kit: Int? = Wire.kit, app: String, id: String, fw: String, does: [String], boot: String? = nil,
                fields: JSONObject = [:]) {
        self.kit = kit
        self.app = app
        self.id = id
        self.fw = fw
        self.does = does
        self.boot = boot
        self.fields = fields
    }
}

/// An `ev` from the device (SPEC.md §3): something happened. Every kind but
/// the kit's `ended` is the app's.
public struct DeviceEvent: Equatable, Sendable {
    /// What happened: `tap`, `talk_on`.
    public var kind: String
    /// What the device already did about it on its own, if it says.
    public var did: String?
    /// The app's details; empty when the message has none.
    public var data: JSONObject

    public init(kind: String, did: String? = nil, data: JSONObject = [:]) {
        self.kind = kind
        self.did = did
        self.data = data
    }
}

/// How a `do` went: the device's `ended` (SPEC.md §4), exactly one for
/// every `do` with an id.
public struct Ended: Equatable, Sendable {
    public enum How: String, Sendable {
        /// It played through, or it was resting and something replaced it.
        case done
        /// Something stopped it early; `why` says what.
        case cut
        /// None of it played; `why` says why.
        case skipped
    }

    /// The `do`'s id, as the host sent it.
    public var id: Int
    public var how: How
    /// A short lower-case word: `now`, `tap`, `late`, `busy`, `full`,
    /// `unknown`, `reset` or the app's own; nil when the device doesn't say.
    public var why: String?

    public init(id: Int, how: How, why: String? = nil) {
        self.id = id
        self.how = how
        self.why = why
    }
}

/// The messages' shapes on the wire (SPEC.md §2–3): building the host's
/// messages and reading the device's.
public enum Wire {
    /// A message is at most this many bytes, its newline aside, either way
    /// (SPEC.md §2).
    public static let maxLine = 512
    /// The protocol version this library speaks (SPEC.md §6).
    public static let kit = 1
    /// A `do`'s ids run 1…this (SPEC.md §3).
    public static let maxId = Int(Int32.max)
    /// A `next` waits this long in the queue when it doesn't say (SPEC.md §3).
    public static let defaultTTL = 5000
    /// The longest `ttl` (SPEC.md §3).
    public static let maxTTL = 60_000

    /// How a `do` joins the queue (SPEC.md §4).
    public enum Play: String, Sendable {
        /// Plays at once, cutting a busy one playing.
        case now
        /// Waits in the queue, for up to its `ttl`.
        case next
        /// Plays only if nothing is playing or the one playing is resting;
        /// else it's skipped.
        case ifFree = "if_free"
    }

    /// A message from the device.
    public enum Message: Equatable, Sendable {
        case hello(Hello)
        /// Any `ev` but `ended`.
        case event(DeviceEvent)
        /// An `ev` whose kind is `ended`, with a valid id and `how`.
        case ended(Ended)
        /// Anything else: `dbg.*` replies passing through the bridge,
        /// types this library doesn't know (an app's older firmware may say
        /// something of its own where a `hello` would be), a malformed
        /// `ended`, and lines that aren't JSON (a board's boot messages).
        case other(String)
    }

    /// The host's bare `hello`: asks the device to say its own on this
    /// link, whether or not it already counts the host as there (SPEC.md §3).
    public static let hello = #"{"t":"hello"}"#

    /// A `state` message: `{"t":"state",` then the app's fields in their
    /// order. A `t` among them is left out, since it's the message's.
    public static func state(_ fields: JSONObject) -> String {
        var out = #"{"t":"state""#
        fields.removingType.writeFields(to: &out, first: false)
        out += "}"
        return out
    }

    /// A `do` message, fields in SPEC.md §3's order. `ttl` goes only with
    /// `next`, the one play it means something for, and `args` only when
    /// there are some.
    public static func `do`(id: Int, name: String, play: Play, ttl: Int, args: JSONObject) -> String {
        var out = #"{"t":"do","id":"# + String(id) + #","name":"#
        JSON.quote(name, to: &out)
        out += #","play":""# + play.rawValue + "\""
        if play == .next { out += #","ttl":"# + String(ttl) }
        if !args.isEmpty {
            out += #","args":"#
            args.write(to: &out)
        }
        out += "}"
        return out
    }

    /// Reads one message from the device. Fields it doesn't know are ignored
    /// (SPEC.md §2).
    public static func decode(_ line: String) -> Message {
        guard line.hasPrefix("{"), let object = JSON.parse(line)?.object, let type = object["t"]?.string
        else { return .other(line) }
        switch type {
        case "hello":
            var fields = object
            for key in ["t", "kit", "app", "id", "fw", "does", "boot"] { fields[key] = nil }
            return .hello(Hello(kit: object["kit"]?.int,
                                app: object["app"]?.string ?? "",
                                id: object["id"]?.string ?? "",
                                fw: object["fw"]?.string ?? "",
                                does: object["does"]?.array?.compactMap(\.string) ?? [],
                                boot: object["boot"]?.string,
                                fields: fields))
        case "ev":
            guard let kind = object["kind"]?.string else { return .other(line) }
            let data = object["data"]?.object ?? [:]
            guard kind == "ended" else {
                return .event(DeviceEvent(kind: kind, did: object["did"]?.string, data: data))
            }
            guard let id = data["id"]?.int, (1...maxId).contains(id),
                  let how = data["how"]?.string.flatMap(Ended.How.init(rawValue:))
            else { return .other(line) }
            return .ended(Ended(id: id, how: how, why: data["why"]?.string))
        default:
            return .other(line)
        }
    }
}

extension JSONObject {
    var removingType: JSONObject {
        guard self["t"] != nil else { return self }
        var copy = self
        copy["t"] = nil
        return copy
    }
}
