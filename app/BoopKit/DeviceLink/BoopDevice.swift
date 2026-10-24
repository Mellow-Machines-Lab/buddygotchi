import Foundation
import LinkKit

/// Boop's vocabulary on LinkKit (linkkit/SPEC.md is the
/// protocol under it): what Boop calls its device, the names it plays
/// beside the reactions' own (`DeviceReaction`), and what its `hello` and taps
/// mean to the app. The link itself, with its ids, `ended`s and transports,
/// is LinkKit's `DeviceLink`.
public enum BoopDevice {
    /// The `hello.app` of Boop's firmware.
    public static let app = "boop"
    /// Over Bluetooth the device advertises as `Boop-XXXX`.
    public static let blePrefix = "Boop"

    /// The name a board advertises for its `hello.id`: `b00p-54fe`
    /// advertises as `Boop-54FE`, the same two bytes of its address.
    public static func advertised(_ id: String) -> String? {
        id.firstIndex(of: "-").map { blePrefix + "-" + id[id.index(after: $0)...].uppercased() }
    }
    /// Push-to-talk's face after the Mac's Talk button, and its end when no
    /// reply is coming.
    public static let listening = "listening", stopListening = "stop_listening"
    /// When a rule's reaction plays: push-to-talk's `listening` at once,
    /// cutting what plays, and the rest only if nothing else plays: a late
    /// rule reaction is worse than none.
    public static func play(_ name: String) -> Wire.Play { name == listening ? .now : .ifFree }
    /// Why the device drops the reactions waiting when push-to-talk starts:
    /// a reaction would end `listening`.
    public static let micOn = "mic_on"
    /// How long a brain reaction may wait in the device's queue: a
    /// late reaction is worse than none.
    public static let reactionTTL = 5000

    /// The link to Boop's device over `transport`, or to none.
    public static func link(_ transport: Transport?, log: @escaping (String) -> Void = { _ in }) -> DeviceLink {
        DeviceLink(app: app, transport: transport, log: log)
    }

    /// The `do` id of the brain's finish a tap landed on, when the device
    /// says so (`data.on`): it only dipped the face, and
    /// the tap opens that thread.
    /// Whether a `tap` was BOOT (`src` `button`), not the screen.
    public static func button(tapped ev: DeviceEvent) -> Bool { ev.data["src"]?.string == "button" }

    public static func finish(tapped ev: DeviceEvent) -> Int? {
        guard let on = ev.data["on"]?.int, (1...Wire.maxId).contains(on) else { return nil }
        return on
    }

    /// The number of the request a finger held on the sign dismisses
    /// (`data.attn`, the `attn.id` the sign showed as the touch began), or
    /// nil when the gesture names none. A request's number fits 32 bits.
    public static func request(held ev: DeviceEvent) -> Int? {
        guard let attn = ev.data["attn"]?.int, (1...Int(Int32.max)).contains(attn) else { return nil }
        return attn
    }
}

/// What Boop's device says of itself in its `hello`.
public struct DeviceInfo: Equatable, Sendable {
    /// `b00p-7f3a`: which Boop this body is.
    public var id: String
    public var fw: String
    /// The version of the voice file on its card, `none`
    /// with no card or none readable, or nil from firmware that doesn't say.
    public var voice: String?
    /// Which face it draws: the popover mirrors the gel one, and a demo
    /// recording says which it was made on. Every face draws every mood.
    public enum Face: String, Sendable { case pixel, gel }
    public var face: Face
    /// The character pack its firmware was built with, as `id version`
    /// (`pixel 0.1.0`), or nil from firmware that doesn't say.
    public var pack: String?

    public init(id: String, fw: String, voice: String? = nil, face: Face = .pixel, pack: String? = nil) {
        self.id = id
        self.fw = fw
        self.voice = voice
        self.face = face
        self.pack = pack
    }

    public init(_ hello: Hello) {
        let pack = hello.fields["pack"]?.string.map { "\($0) \(hello.fields["pack_version"]?.string ?? "")" }
        self.init(id: hello.id, fw: hello.fw, voice: hello.fields["voice"]?.string,
                  face: hello.fields["face"]?.string.flatMap(Face.init(rawValue:)) ?? .pixel, pack: pack)
    }

    /// Whether it plays the takes the app picks from: its card has the
    /// same pack as `Take.all`, or it doesn't say.
    public var hasTheVoice: Bool { voice.map { $0 == Take.voiceVersion } ?? true }

    /// The app's character pack, as `pack` names one.
    public static var appPack: String { "\(CharacterPack.active.id) \(CharacterPack.active.version)" }

    /// Whether its firmware was built with the app's character pack, or it
    /// doesn't say. With another, it still works: a mood it doesn't have
    /// draws its startup mood, and the voice has a check of its own.
    public var hasThePack: Bool { pack.map { $0 == Self.appPack } ?? true }

    /// What the log says when it says hello: who it is, and when its
    /// character pack or its card's voice isn't the app's.
    var logLines: [String] {
        ["device: \(id) firmware \(fw)" + (pack.map { " pack \($0)" } ?? "") + (voice.map { " voice \($0)" } ?? "")]
            + (hasThePack ? [] : ["device: its firmware is built with the \(pack!) character pack, the app runs "
                                  + "\(Self.appPack): some of its faces won't match the app's moods"])
            + (hasTheVoice ? [] : ["device: its card's voice is \(voice!), the app's \(Take.voiceVersion): "
                                   + "Boop says nothing until they match"])
    }
}

/// `--link` values: `usb:<bridge socket>`, `ble` or `none`.
public enum LinkSetting: Equatable, Sendable {
    case usb(String)
    case bluetooth
    case none

    public init?(_ text: String) {
        if text.hasPrefix("usb:"), text.count > 4 {
            self = .usb(String(text.dropFirst(4)))
        } else if text == "ble" {
            self = .bluetooth
        } else if text == "none" {
            self = .none
        } else {
            return nil
        }
    }
}

extension DeviceLink.Sender {
    /// Who sent a message, for `debug.jsonl`'s `by` and boop.log: the
    /// core's rules (every `state`, the reactions, push-to-talk), or the
    /// brain's reactions.
    public static let rule: Self = "rule"
    public static let brain: Self = "brain"
}
