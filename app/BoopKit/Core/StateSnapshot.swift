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

    /// The device keeps names in 24-byte fields, and what the needs-you screen
    /// shows (`attn.project` and `attn.name`) in 48-byte ones: three lines
    /// of 16 on the screen.
    public static let maxNameBytes = 23
    public static let maxSignBytes = 47

    /// `text` precomposed (NFC) and cut to at most `max` bytes of UTF-8, on
    /// a character boundary. Finder names folders decomposed (e and
    /// U+0301), which the device would draw as "e?"; precomposed, é shows as
    /// e. Control characters, which the device can't draw and JSON escapes
    /// to six bytes each, become spaces. With `marked`, a cut text ends in
    /// "..", within those bytes, so the device shows it was cut, and it's
    /// cut where the board cuts its own text (`cutAt`).
    public static func clip(_ text: String, marked: Bool = false, max: Int = maxNameBytes) -> String {
        var text = text.precomposedStringWithCanonicalMapping
        if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            text = String(String.UnicodeScalarView(text.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : $0 }))
        }
        guard text.utf8.count > max else { return text }
        let chars = Array(text)
        let room = marked ? max - 2 : max
        var fit = 0, bytes = 0
        while fit < chars.count, bytes + chars[fit].utf8.count <= room {
            bytes += chars[fit].utf8.count
            fit += 1
        }
        return marked ? String(chars[..<cutAt(chars, fit)]) + ".." : String(chars[..<fit])
    }

    /// How many of `chars` to keep when they're cut to at most `most`, ".."
    /// after them: the board's rule for its own text (render::cutAt), a
    /// character for a glyph. At the end of the last word within them after
    /// the last "·", when that keeps at least half; else mid-word; never on
    /// a space or a "·".
    static func cutAt(_ chars: [Character], _ most: Int) -> Int {
        var word = 0, solid = 0
        var prev: Character = " "
        for i in 0...most {
            let c: Character? = i < chars.count ? chars[i] : nil
            if c == "·" {
                word = 0  // the cut stays in what follows the last "·"
            } else if c == nil || c == " ", prev != " ", prev != "·" {
                word = i  // a word ends before character i
            }
            guard let c else { break }
            if c != " ", c != "·", i < most { solid = i + 1 }
            prev = c
        }
        return word > 0 && 2 * word >= most ? word : solid
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
    /// Sessions working.
    public var busy: Int
    /// Sessions idle: their turn ended, and they wait for your next prompt.
    public var idle: Int
    /// Helpers (subagents) working, over every session.
    public var helpers: Int
    public var vol: Int
    /// What's true now (`Occasions`): the part of the day, a holiday, how
    /// busy the agents are. The device shows the designs whose tags are
    /// all on, and picks each look's variation itself.
    public var when: [String]
    /// An agent's to-do list, as counts.
    public struct Todo: Equatable, Sendable {
        public var done: Int
        public var total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        /// As the board draws it, and demos and evals write it: `3/7`.
        public var text: String { "\(done)/\(total)" }

        /// A list written `3/7`: done, of a total of 1 or more.
        public init?(text: String) {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]), total >= 1, (0...total).contains(done)
            else { return nil }
            self.init(done: done, total: total)
        }
    }

    /// The to-do list of the longest turn working that has one, while
    /// nothing needs you; nil sends none.
    public var todo: Todo?

    /// A working session's lane in the work stream (`WorkStream`): its
    /// slot, which picks its column and colour on the board, how many
    /// calls it has made (the board drops a word for each new one), and
    /// its latest call's word. Never whose: its colour tells it apart.
    public struct Call: Equatable, Sendable {
        public var slot: Int
        public var count: Int
        public var word: String

        public init(slot: Int, count: Int, word: String) {
            self.slot = slot
            self.count = count
            self.word = word
        }
    }

    /// The lanes, while the agents work and nothing needs you; none sends
    /// none.
    public var calls: [Call]

    public init(base: String, act: String? = nil, mood: String, attn: Attention?, busy: Int, idle: Int = 0, helpers: Int = 0,
                vol: Int, when: [String] = [], todo: Todo? = nil, calls: [Call] = []) {
        self.base = base
        self.act = act
        self.mood = mood
        self.attn = attn
        self.busy = busy
        self.idle = idle
        self.helpers = helpers
        self.vol = vol
        self.when = when
        self.todo = todo
        self.calls = calls
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
        if idle > 0 { fields["idle"] = .int(idle) }
        if helpers > 0 { fields["helpers"] = .int(helpers) }
        fields["vol"] = .int(vol)
        if !when.isEmpty { fields["when"] = .array(when.map { .string($0) }) }
        if let todo { fields["todo"] = .object(["done": .int(todo.done), "total": .int(todo.total)]) }
        if !calls.isEmpty {
            fields["calls"] = .array(calls.map { .array([.int($0.slot), .int($0.count), .string($0.word)]) })
        }
        return fields
    }

    /// The message as one JSON line, keys in the protocol's order.
    public var jsonLine: String { Wire.state(fields) }
}
