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
        /// What the request asks of you, so a glance says how long it'll
        /// take; nil when it isn't known (a request from before, or practice).
        public var kind: Kind?

        /// What a request asks of you: to say yes or no to a call, to
        /// answer a question, or to read a plan.
        public enum Kind: String, Sendable, CaseIterable {
            case approve, question, plan

            /// Every kind's words, for a test of their length.
            public static var allWords: [String] { allCases.map(\.words) }

            /// The words for it, after "needs you": short enough for the
            /// board's card (16 characters at most).
            public var words: String {
                switch self {
                case .approve: "a yes or no"
                case .question: "a question"
                case .plan: "a plan to read"
                }
            }

            /// The kind of a request, from what it asks for and the tools
            /// asking: a plan when Claude asks to leave plan mode, a
            /// question when it asks for input or asks you something, else
            /// a call to allow.
            public static func of(asking: String?, tools: [String]) -> Kind {
                if tools.contains("ExitPlanMode") { return .plan }
                if asking == "input" || tools.contains("AskUserQuestion") { return .question }
                return .approve
            }
        }

        public init(agent: String, project: String, name: String = "", more: Int, id: Int = 0, kind: Kind? = nil) {
            self.agent = agent
            self.project = project
            self.name = name
            self.more = more
            self.id = id
            self.kind = kind
        }
    }

    /// The device keeps names in 24-byte fields, and what the needs-you screen
    /// shows (`attn.project` and `attn.name`) in 48-byte ones: three lines
    /// of 16 on the screen.
    public static let maxNameBytes = 23
    public static let maxSignBytes = 47
    /// A finish's thread (`who.thread`): what the gel's low sign holds on
    /// two lines, and the device keeps in a field of 52 bytes.
    public static let maxThreadBytes = 50

    /// `text` precomposed (NFC) and cut to at most `max` bytes of UTF-8, on
    /// a character boundary. Finder names folders decomposed (e and
    /// U+0301), which the device would draw as "e?"; precomposed, é shows as
    /// e. Control characters, which the device can't draw and JSON escapes
    /// to six bytes each, become spaces. With `marked`, a cut text ends in
    /// "..", within those bytes, so the device shows it was cut, and it's
    /// cut where the board cuts its own text (`cutAt`), and it's drawable
    /// first (`drawable`): it's going to the board.
    public static func clip(_ text: String, marked: Bool = false, max: Int = maxNameBytes) -> String {
        var text = marked ? drawable(text) : text.precomposedStringWithCanonicalMapping
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

    /// `text` precomposed, with what the board's fonts would draw as "?"
    /// made plain or left out: curly quotes, dashes, an ellipsis and a
    /// no-break space as the plain marks they stand for (`Signs.plain`),
    /// and emoji, with their joiners and variation selectors, gone, as
    /// are marks that draw nothing (zero-width spaces, direction marks), the
    /// spaces they leave closed up. "Don’t ship it 🚀" shows as "Don't
    /// ship it", not "Don?t ship it ?".
    public static func drawable(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            if let mark = Signs.plain[s] {
                out.append(contentsOf: mark.unicodeScalars)
            } else if s.properties.generalCategory == .format || (0xFE00...0xFE0F).contains(s.value)
                        || s.properties.isEmojiModifier
                        || (s.value >= 0x2000 && s.properties.isEmoji) {
                continue
            } else {
                out.append(s)
            }
        }
        let plain = String(out)
        guard plain != text else { return plain }
        return plain.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Whether the board's fonts draw `c`: Latin, with its accents folded,
    /// and the common punctuation.
    static func drawn(_ c: Unicode.Scalar) -> Bool {
        (0x20...0x24F).contains(c.value) || (0x2010...0x2027).contains(c.value)
    }

    /// A thread's name for the board, or nil when, made `drawable`, it's
    /// nothing or mostly what its fonts lack (CJK, another script), each a
    /// "?": its project shows instead. The Mac's own windows keep the name.
    public static func boardName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let shown = drawable(name).filter { !$0.isWhitespace }
        guard !shown.isEmpty else { return nil }
        let drawnCount = shown.filter { $0.unicodeScalars.allSatisfy(drawn) }.count
        return drawnCount * 2 >= shown.count ? name : nil
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

    /// What Boop is busy with, `asleep`, `idle` or `working`: the wire's
    /// `base`.
    public var doing: String
    /// How the agents are working, one of `Act`'s names, only while
    /// `doing` is `working` and nothing needs you: the look shows it in
    /// working's place. Nil sends none. The wire's `act`.
    public var activity: String?
    /// Boop's mood, one of the pack's moods, which
    /// picks the set of faces the device draws everything in.
    public var mood: String
    public var attn: Attention?
    /// Sessions working.
    public var working: Int
    /// Sessions idle: their turn ended, and they wait for your next prompt.
    public var idle: Int
    /// Helpers (subagents) working, over every session.
    public var helpers: Int
    public var vol: Int
    /// The buddy's colour, 0 to 7 (`BuddyColor`): sent only when it isn't 0.
    public var color = 0
    /// What's true now (`Tags`): the part of the day, a holiday, how
    /// busy the agents are. The device shows the designs whose tags are
    /// all on, and picks each look's variation itself.
    public var when: [String]
    /// The way to your pointer while it moves and Boop knows where it sits
    /// (`Along`, `Anchor`): the board's eyes follow it. Nil sends none.
    /// The wire's `ptr`: `[x, y]`, or `[x, y, 1]` at the edge nearest Boop.
    public var pointer: Pointer?
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
    /// Today's ring, the day's XP in whole percent (`Growth.percent`): the
    /// board's bar, which comes when it moves. Nil sends none.
    public var xp: Int?
    /// The wish waiting, by its kind, while its wait counts: the board
    /// shows its icon then, and times nothing.
    public var wish: String?
    /// One agent's pip on the strip's line (`Core.watchFields`): `w`
    /// working, `c` holding a card, `i` idle, `a` wanting you (waiting on
    /// you, or news you haven't seen); and its lane's slot, its colour.
    public struct Pip: Equatable, Sendable {
        public var kind: Character
        public var slot: Int?
    }
    /// The pips, with two agents or more; none with one.
    public var pips: [Pip] = []
    /// Which pip the screen follows, and its name for the strip's chip.
    public var watch: Int?
    public var watchName: String?
    /// A pill: news from an agent you aren't watching, by its pip.
    public struct Pill: Equatable, Sendable {
        public var at: Int
        public var text: String
    }
    public var pill: Pill?
    /// Boop's energy when it isn't normal, `bright` or `tired` (`Energy`):
    /// the board draws it on the lids and in the tempo. Nil sends none.
    public var energy: String?

    /// What you call the buddy, when that isn't the pack's own name, which the
    /// board knows: its own captions say it. Nil sends none.
    public var buddy: String?

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

    /// The work act running or its result (`WorkStream.Act`): which, what its
    /// sign says, and how it ended, `p` or `f`.
    public struct WorkAct: Equatable, Sendable {
        public var kind: String
        public var words: String
        public var result: String?

        public init(kind: String, words: String, result: String? = nil) {
            self.kind = kind
            self.words = words
            self.result = result
        }
    }

    /// The act, while nothing else holds the screen.
    public var workAct: WorkAct?
    /// The card Boop holds, while nothing needs you.
    public var card: CardShow?

    /// One session in the board's agents' drawer: its number there, the one
    /// a tap on its row sends back (`ev drawer` `pick`), whether it needs
    /// you, works or rests (`n`, `w`, `i`), its work stream lane's slot,
    /// whose colour it wears (-1 for none), its agent, its thread's name
    /// (else its project) and its second line: its card's words while it
    /// has a card, else its project (`""` when that's the title).
    public struct Row: Equatable, Sendable {
        public var id: Int
        public var status: String
        public var slot: Int
        public var agent: String
        public var title: String
        public var project: String

        public init(id: Int, status: String, slot: Int = -1, agent: String, title: String, project: String = "") {
            self.id = id
            self.status = status
            self.slot = slot
            self.agent = agent
            self.title = title
            self.project = project
        }
    }

    /// The drawer's rows, only while the board says it's open: then an
    /// empty list is sent too, so the board knows the Mac heard. A window
    /// of at most `maxRows`, from the row the board asked for, as it
    /// scrolls.
    public var list: [Row]?
    /// The sessions before the rows and after them: the board scrolls
    /// through them all, asking for the rows it comes to.
    public var skip: Int
    public var unlisted: Int
    public static let maxRows = 6
    /// The longest title and project a row carries, in bytes, as the
    /// board's fields hold them.
    public static let maxTitleBytes = 30, maxProjectBytes = 22

    public init(doing: String, activity: String? = nil, mood: String, attn: Attention?, working: Int, idle: Int = 0, helpers: Int = 0,
                vol: Int, color: Int = 0, when: [String] = [], todo: Todo? = nil, calls: [Call] = [], list: [Row]? = nil,
                skip: Int = 0, unlisted: Int = 0) {
        self.doing = doing
        self.activity = activity
        self.mood = mood
        self.attn = attn
        self.working = working
        self.idle = idle
        self.helpers = helpers
        self.vol = vol
        self.color = color
        self.when = when
        self.todo = todo
        self.calls = calls
        self.list = list
        self.skip = skip
        self.unlisted = unlisted
    }

    /// The look the device shows when nothing needs you: what the agents
    /// are doing, else what Boop is.
    public var look: String { activity ?? doing }

    /// The visual the device shows for it: needs you's while something
    /// does, else the look.
    public var visual: String { attn != nil ? "needs_you" : look }

    /// You're on a call (`Along`): Boop holds still and says nothing.
    public var onCall: Bool { when.contains("oncall") }
    /// You're speaking to another app (`Along`): Boop nods along and says
    /// nothing, so no dictation hears it.
    public var speaking: Bool { when.contains("speaking") }

    /// How many sessions need you: `attn`'s and its `more`. The popover's
    /// headline; the message doesn't carry it.
    public var waiting: Int { attn.map { $0.more + 1 } ?? 0 }

    /// The card Boop holds (`Cards`): whose it is, by its lane's slot (-1
    /// with no lane), what it says, and where it is among the cards showing.
    /// The live picture Boop holds of the watched agent's work (`pic`,
    /// `Core.picture`): its lane's slot and its agent, for its window.
    public struct PictureShow: Equatable, Sendable {
        public var slot: Int
        public var agent: String
        public var picture: Core.Picture
    }
    public var pic: PictureShow?

    public struct CardShow: Equatable, Sendable {
        public var slot: Int
        /// Whose it is, `claude` or `codex`: the board names the agent on
        /// the card, so it reads as the agent's and not Boop's.
        public var agent: String = ""
        public var result: Bool
        public var text: String
        public var small: String?
        public var over: Bool
        public var index: Int
        public var count: Int
    }

    /// The message's fields after its `t`, in the protocol's order: the
    /// app's part of LinkKit's `state` (linkkit/SPEC.md §3).
    public var fields: JSONObject {
        var fields: JSONObject = ["base": .string(doing)]
        if let activity { fields["act"] = .string(activity) }
        fields["mood"] = .string(mood)
        if let attn {
            var a: JSONObject = ["agent": .string(attn.agent), "project": .string(attn.project)]
            if !attn.name.isEmpty { a["name"] = .string(attn.name) }
            a["more"] = .int(attn.more)
            if attn.id > 0 { a["id"] = .int(attn.id) }
            if let kind = attn.kind { a["kind"] = .string(kind.rawValue) }
            fields["attn"] = .object(a)
        }
        fields["busy"] = .int(working)  // the wire calls the count busy
        if idle > 0 { fields["idle"] = .int(idle) }
        if helpers > 0 { fields["helpers"] = .int(helpers) }
        // On a call, or while you speak, Boop is silent: the board plays no
        // voice and no sound.
        fields["vol"] = .int(onCall || speaking ? 0 : vol)
        if color != 0 { fields["color"] = .int(color) }
        let tags = when.filter(Tags.board.contains)  // the tags the board reads
        if !tags.isEmpty { fields["when"] = .array(tags.map { .string($0) }) }
        if let pointer {
            fields["ptr"] = .array([.int(pointer.x), .int(pointer.y)] + (pointer.near ? [.int(1)] : []))
        }
        if let xp { fields["xp"] = .int(xp) }
        if let todo { fields["todo"] = .object(["done": .int(todo.done), "total": .int(todo.total)]) }
        if let buddy { fields["buddy"] = .string(buddy) }
        if let wish { fields["wish"] = .string(wish) }
        if let energy { fields["energy"] = .string(energy) }
        if !pips.isEmpty {
            // "w0", "i-": each pip its kind and its slot, "-" for none.
            fields["pips"] = .string(pips.map { "\($0.kind)\($0.slot.map(String.init) ?? "-")" }.joined())
            if let watch { fields["watch"] = .int(watch) }
            if let watchName { fields["who"] = .string(watchName) }
            if let pill { fields["pill"] = .array([.int(pill.at), .string(pill.text)]) }
        }
        if !calls.isEmpty {
            fields["calls"] = .array(calls.map { .array([.int($0.slot), .int($0.count), .string($0.word)]) })
        }
        if let workAct {
            var wact: [JSONObject.Value] = [.string(workAct.kind), .string(workAct.words)]
            if let result = workAct.result { wact.append(.string(result)) }
            fields["wact"] = .array(wact)
        }
        if let list {
            fields["list"] = .array(list.map {
                .array([.int($0.id), .string($0.status), .int($0.slot), .string($0.agent), .string($0.title),
                        .string($0.project)])
            })
        }
        if let card {
            var c: JSONObject = ["a": .int(card.slot), "k": .string(card.result ? "r" : "s"), "t": .string(card.text)]
            if !card.agent.isEmpty { c["g"] = .string(card.agent) }
            if let small = card.small { c["d"] = .string(small) }
            if card.over { c["o"] = .int(1) }
            c["at"] = .array([.int(card.index), .int(card.count)])
            fields["card"] = .object(c)
        }
        if let pic {
            // ["p", slot, agent, done, total, step, left] · ["c", slot,
            // agent, file, added, removed, …] · ["h", slot, agent, working, done]
            var p: [JSONObject.Value]
            switch pic.picture {
            case let .plan(done, total, step, left):
                p = [.string("p"), .int(pic.slot), .string(pic.agent), .int(done), .int(total),
                     .string(step.map { StateSnapshot.clip($0, max: 24) } ?? "")]
                if let left { p.append(.int(left)) }
            case let .changes(files):
                p = [.string("c"), .int(pic.slot), .string(pic.agent)]
                for f in files { p += [.string(StateSnapshot.clip(f.name, max: 16)), .int(f.added), .int(f.removed)] }
            case let .helpers(working, done):
                p = [.string("h"), .int(pic.slot), .string(pic.agent), .int(working), .int(done)]
            }
            fields["pic"] = .array(p)
        }
        if skip > 0 { fields["skip"] = .int(skip) }
        if unlisted > 0 { fields["unlisted"] = .int(unlisted) }
        return fields
    }

    /// The tags of you at the Mac that the logs and a bug report don't keep
    /// (`unnoticed`): what you scroll, play, record or copy.
    public static let unloggedTags = Tags.along

    /// `line`, a `state`, as the logs keep it: without the pointer (`ptr`)
    /// and the tags of what you scroll, play, record or copy, so no log or
    /// bug report holds a timeline of you at the Mac. Any other line as it is.
    public static func unnoticed(_ line: String) -> String {
        guard line.hasPrefix(#"{"t":"state""#), line.contains(#""ptr":"#) || unloggedTags.contains(where: { line.contains("\"\($0)\"") })
        else { return line }
        var out = line.replacingOccurrences(of: #","ptr":\[[-0-9,]*\]"#, with: "", options: .regularExpression)
        for tag in unloggedTags {
            out = out.replacingOccurrences(of: ",\"\(tag)\"", with: "").replacingOccurrences(of: "\"\(tag)\",", with: "")
                .replacingOccurrences(of: ",\"when\":[\"\(tag)\"]", with: "")
        }
        return out
    }

    /// The message as one JSON line, keys in the protocol's order.
    public var jsonLine: String { Wire.state(fields) }

    /// Whether the line fits the board's: one that doesn't is never sent.
    public var fits: Bool { jsonLine.utf8.count < Wire.maxLine }
}
