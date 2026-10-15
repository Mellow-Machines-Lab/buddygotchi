import Foundation
import LinkKit

/// The `state` message: the whole picture the device draws.
public struct StateSnapshot: Equatable, Sendable {
    public struct Attention: Equatable, Sendable {
        public var agent: String
        public var project: String
        /// The thread's name, which the device shows in the project's
        /// place; `""` for none, and then the message doesn't carry it.
        public var name: String
        public var more: Int
        /// The request shown's number, counting up from a random one each
        /// launch: a new one is a different request, which the face knocks for again.
        /// 0 sends none.
        public var id: Int

        public init(agent: String, project: String, name: String = "", more: Int, id: Int = 0) {
            self.agent = agent
            self.project = project
            self.name = name
            self.more = more
            self.id = id
        }
    }

    /// The device keeps names in 24-byte fields, and what needs you's sign
    /// shows (`attn.project` and `attn.name`) in 48-byte ones: three lines
    /// of 16 on the sign.
    public static let maxNameBytes = 23
    public static let maxSignBytes = 47

    /// `text` precomposed (NFC) and cut to at most `max` bytes of UTF-8, on
    /// a character boundary. Finder names folders decomposed (e and
    /// U+0301), which the device would draw as "e?"; precomposed, é shows as
    /// e. Control characters, which the device can't draw and JSON escapes
    /// to six bytes each, become spaces. With `marked`, a cut text ends in
    /// "..", within those bytes, so the device shows it was cut.
    public static func clip(_ text: String, marked: Bool = false, max: Int = maxNameBytes) -> String {
        var text = text.precomposedStringWithCanonicalMapping
        if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            text = String(String.UnicodeScalarView(text.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : $0 }))
        }
        guard text.utf8.count > max else { return text }
        let room = marked ? max - 2 : max
        var out = ""
        for ch in text {
            if out.utf8.count + String(ch).utf8.count > room { break }
            out.append(ch)
        }
        return marked ? out + ".." : out
    }

    /// `asleep`, `idle` or `working`.
    public var base: String
    /// What the agents are doing, one of `Act`'s names, only while `base`
    /// is `working` and nothing needs you: the look shows it in working's
    /// place. Nil sends none.
    public var act: String?
    /// Boop's mood, one of the pack's moods, which
    /// picks the set of faces the device draws everything in.
    public var mood: String
    public var attn: Attention?
    public var busy: Int
    public var vol: Int
    /// Which variation of the visual shows, from 1: needs you's while
    /// something needs you, else the look's. The core
    /// picks it at random when the visual changes.
    public var variant: Int

    public init(base: String, act: String? = nil, mood: String, attn: Attention?, busy: Int, vol: Int,
                variant: Int = 1) {
        self.base = base
        self.act = act
        self.mood = mood
        self.attn = attn
        self.busy = busy
        self.vol = vol
        self.variant = variant
    }

    /// The look the device shows when nothing needs you: what the agents
    /// are doing, else the base.
    public var look: String { act ?? base }

    /// The visual the device shows for it: needs you's while something
    /// does, else the look.
    public var visual: String { attn != nil ? "needs_you" : look }

    /// How many sessions need you: `attn`'s and its `more`. The popover's
    /// headline; the message doesn't carry it.
    public var waiting: Int { attn.map { $0.more + 1 } ?? 0 }

    /// The message's fields after its `t`, in the protocol's order: the
    /// app's part of LinkKit's `state` (linkkit/SPEC.md §3).
    public var fields: JSONObject {
        var fields: JSONObject = ["base": .string(base)]
        if let act { fields["act"] = .string(act) }
        fields["mood"] = .string(mood)
        if let attn {
            var a: JSONObject = ["agent": .string(attn.agent), "project": .string(attn.project)]
            if !attn.name.isEmpty { a["name"] = .string(attn.name) }
            a["more"] = .int(attn.more)
            if attn.id > 0 { a["id"] = .int(attn.id) }
            fields["attn"] = .object(a)
        }
        fields["busy"] = .int(busy)
        fields["vol"] = .int(vol)
        fields["variant"] = .int(variant)
        return fields
    }

    /// The message as one JSON line, keys in the protocol's order.
    public var jsonLine: String { Wire.state(fields) }
}
