import AgentHooks
import Foundation

/// A card an agent hands Boop to hold (plan/agent-cards.md): one main thing,
/// short enough to read from a chair, and at most one small line under it.
/// An agent sends one through the `boop-cards` tool server (`CardTool`); the
/// to-do card is Boop's own, from the hooks. A card's words are the
/// agent's: they go to the screen and never to the brain.
public struct Card: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// What the agent is on now, while its turn runs.
        case status
        /// What the turn made, held up after its finish.
        case result
    }

    public var kind: Kind
    /// The main thing: what it's doing, or the result's headline.
    public var text: String
    /// A status's place in the agent's own plan: step `step` of `of`.
    public var step: Int?
    public var of: Int?
    /// A status's guess at the minutes left, as the agent gave it: counted
    /// down as it stands, never corrected.
    public var minutes: Int?
    /// A result's second line.
    public var detail: String?
    /// What a tap on a result opens: a web page, or a file.
    public var link: String?
    /// A result's part in Boop's mind (documentation/design/brain.md, layer
    /// 2), each optional and each the agent's own: lines Boop might say
    /// about the turn, which Boop picks from or not; how the person seemed;
    /// and one thing about them worth keeping, for the dream to judge. None
    /// of it is ever the brain's to read.
    public var lines: [Line] = []
    public var seemed: Seemed?
    public var remember: String?

    /// A line an agent offers for Boop to say, in one of the pack's faces.
    public struct Line: Equatable, Sendable {
        public var says: String
        public var feeling: String
        public init(says: String, feeling: String) {
            self.says = says
            self.feeling = feeling
        }
    }

    /// How the person seemed this turn, as the agent read them.
    public enum Seemed: String, CaseIterable, Sendable {
        case pleased, plain, frustrated, rushed, kind
    }

    /// The most lines a result offers; the longest line (the gel's low
    /// sign's room, `MemoryPipeline.signMax`); the longest note
    /// (`MemoryEdits.maxLength`).
    public static let linesMost = 2, saysMost = 40, rememberMost = 140

    /// The most characters the main thing and the small line keep.
    public static let textMost = 24, detailMost = 28
    /// The most a link keeps, and the schemes a tap may open.
    public static let linkMost = 300
    public static let steps = 1...99, minutesRange = 0...600

    public init(kind: Kind, text: String, step: Int? = nil, of: Int? = nil, minutes: Int? = nil, detail: String? = nil,
                link: String? = nil) {
        self.kind = kind
        self.text = text
        self.step = step
        self.of = of
        self.minutes = minutes
        self.detail = detail
        self.link = link
    }

    /// The card as its tool's arguments, which `make` reads back.
    var args: [String: Any] {
        var args: [String: Any] = [kind == .status ? "doing" : "headline": text]
        args["step"] = step
        args["of"] = of
        args["minutes_left"] = minutes
        args["detail"] = detail
        args["link"] = link
        if !lines.isEmpty { args["boop_lines"] = lines.map { ["says": $0.says, "feeling": $0.feeling] } }
        args["you_seemed"] = seemed?.rawValue
        args["remember"] = remember
        return args
    }

    /// A card from a tool call's arguments, held to the limits: text is one
    /// line, cut at a word where it can be; numbers outside their range and a
    /// link that isn't a web page or a path are left out. Nil with no text.
    /// `faces` are the pack's: an offered line's feeling must be one. The
    /// tool server, which loads no pack, passes the brief's or none (any
    /// plain word), and Boop holds the card to its own pack as it reads it.
    public static func make(_ kind: Kind, _ args: [String: Any], faces: Set<String>? = nil) -> Card? {
        func line(_ key: String, _ most: Int) -> String? {
            guard let raw = args[key] as? String else { return nil }
            // As the board's fonts draw it, before it's measured.
            let words = StateSnapshot.drawable(raw).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
            return words.isEmpty ? nil : cut(words, to: most)
        }
        func number(_ key: String, _ range: ClosedRange<Int>) -> Int? {
            let n = (args[key] as? NSNumber).map { Int($0.doubleValue.rounded()) }
            return n.flatMap { range.contains($0) ? $0 : nil }
        }
        guard let text = line(kind == .status ? "doing" : "headline", textMost) else { return nil }
        var card = Card(kind: kind, text: text)
        switch kind {
        case .status:
            card.step = number("step", steps)
            card.of = number("of", steps)
            if let step = card.step, let of = card.of, step > of { (card.step, card.of) = (nil, nil) }
            if card.step == nil || card.of == nil { (card.step, card.of) = (nil, nil) }
            card.minutes = number("minutes_left", minutesRange)
        case .result:
            card.detail = line("detail", detailMost)
            card.link = (args["link"] as? String).flatMap(openable)
            card.lines = Self.lines(args["boop_lines"], faces: faces)
            card.seemed = (args["you_seemed"] as? String).flatMap { Seemed(rawValue: $0.lowercased()) }
            card.remember = (args["remember"] as? String).flatMap(Self.note)
        }
        return card
    }

    /// The lines an agent offers, held to the checks a remembered line
    /// passes: one line of printable ASCII within `saysMost`, nothing
    /// private, no order and no secret, and a feeling that is one of the
    /// pack's faces. One that fails is dropped, never cut.
    static func lines(_ raw: Any?, faces: Set<String>?) -> [Line] {
        let items = raw as? [Any] ?? []
        return items.prefix(linesMost).compactMap { item in
            guard let o = item as? [String: Any], let says = (o["says"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let feeling = (o["feeling"] as? String)?.lowercased(), faces?.contains(feeling) ?? feeling.allSatisfy(\.isLetter),
                  says.count <= saysMost, MemoryPipeline.signIsValid(says), MemoryPipeline.mayKeep(says) else { return nil }
            return Line(says: says, feeling: feeling)
        }
    }

    /// The note an agent offers, if it may be kept: one line, within
    /// `rememberMost`, nothing private, no order and no secret.
    static func note(_ raw: String) -> String? {
        let t = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= rememberMost, MemoryPipeline.mayKeep(t) else { return nil }
        return t
    }

    /// `text` in at most `most` characters, cut after a whole word where one
    /// ends in its second half, with ".." for what's gone, as the board
    /// marks its own cuts.
    static func cut(_ text: String, to most: Int) -> String {
        guard text.count > most else { return text }
        let kept = text.prefix(most - 2)
        if text.dropFirst(most - 2).first == " " { return kept + ".." }
        if let space = kept.lastIndex(of: " "), kept.distance(from: kept.startIndex, to: space) >= most / 2 {
            return kept[..<space] + ".."
        }
        return kept + ".."
    }

    /// A link a tap may open: an http or https page, or a path. Nothing
    /// else, and nothing longer than `linkMost`.
    static func openable(_ link: String) -> String? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty, link.count <= linkMost, !link.contains(where: \.isNewline) else { return nil }
        if link.hasPrefix("/") || link.hasPrefix("~/") { return link }
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return link
    }
}

/// The tools an agent sees (`boop-cards`, a Model Context Protocol server
/// over stdio): what each is for and takes, in the words the agent reads.
/// Those words are the whole of how an agent learns to use a card, so they
/// say when to call and how short to be.
public enum CardTool {
    /// What the server tells the agent as it connects.
    public static let instructions: String = """
        Boop is a small desk companion with a screen that sits beside the person you're working for. It shows them what \
        you're doing, so they don't have to watch the terminal. In every turn that takes more than a couple of tool \
        calls: call `status` as you begin, and again each time you move to a different step; and call `result` once, \
        right before your final message, saying honestly how it went. Skip them only for a quick answer. Both return \
        at once and need no reply.
        """ + showInstructions

    /// The few words Claude reads at each session's start, from
    /// `contextFile` in the state folder (`agent-hook --context`): the
    /// tool server's own instructions alone got a card from about one turn
    /// in three; with this line in what the agent reads, every turn of work.
    public static let context = """
        The person you're working for has a desk companion called Boop that shows them what you're doing. Use the \
        boop-cards status tool as you start and as you move between steps. In a turn that used tools, call the \
        boop-cards show tool once with one small picture of what the turn made, found or decided, then the result \
        tool once, just before your final message.
        """
    public static let contextFile = "agent-context.txt"

    public static var tools: [[String: Any]] { cardTools + [showTool] }

    static var cardTools: [[String: Any]] { [
        [
            "name": "status",
            "description": """
                Show the person what you're working on right now, on their desk companion's screen. Call it when you \
                start, and again when you move to a different step. Keep `doing` short and plain, like "fixing the \
                nav overflow" or "running the tests": at most 24 characters, no file paths or code. If you have a \
                plan, give `step` and `of`. If you can guess how long the rest of this turn will take, give \
                `minutes_left`: a rough guess is fine.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "doing": ["type": "string", "description": "What you're doing now, in a few plain words (at most 24 characters)."],
                    "step": ["type": "integer", "description": "Which step of your plan this is, from 1."],
                    "of": ["type": "integer", "description": "How many steps your plan has."],
                    "minutes_left": ["type": "number", "description": "Your guess at the minutes left in this turn."],
                ],
                "required": ["doing"],
            ] as [String: Any],
        ],
        [
            "name": "result",
            "description": """
                Show the person what this turn produced, on their desk companion's screen. Call it once, just before \
                your final message. `headline` is the outcome in a few plain words, like "nav overflow fixed" or \
                "couldn't reproduce it": at most 24 characters, and say so honestly when it didn't work. `detail` is \
                one more short line, like "3 files, 212 tests green". If the turn made something they can open (a \
                pull request, a preview page, a file), give its URL or path as `link`. On a turn that did real work \
                you may also fill `boop_lines`, `you_seemed` and `remember`, as the server's instructions say; leave \
                them out on a quick answer.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "headline": ["type": "string", "description": "The outcome in a few plain words (at most 24 characters)."],
                    "detail": ["type": "string", "description": "One more short line (at most 28 characters)."],
                    "link": ["type": "string", "description": "A URL or file path the person can open to see the result."],
                    "boop_lines": [
                        "type": "array", "maxItems": Card.linesMost,
                        "description": "Two things Boop might say about this turn, in its own voice and different feelings, one of them doubtful. Boop picks one, or neither.",
                        "items": ["type": "object", "required": ["says", "feeling"], "properties": [
                            "says": ["type": "string", "description": "At most \(Card.saysMost) characters, plain lower case."],
                            "feeling": ["type": "string", "description": "One of Boop's faces, as the server's instructions list them."],
                        ] as [String: Any]] as [String: Any],
                    ] as [String: Any],
                    "you_seemed": ["type": "string", "enum": Card.Seemed.allCases.map(\.rawValue), "description": "How the person seemed this turn."],
                    "remember": ["type": "string", "description": "One plain sentence worth keeping about the person or their work, starting with You, at most \(Card.rememberMost) characters. Only if there is one."],
                ],
                "required": ["headline"],
            ] as [String: Any],
        ],
    ] }

    /// What `instructions` say of `show`: as firm as the rest, since "you may" got almost no cards in the first
    /// trial (plan/agent-cards.md).
    public static let showInstructions = """
         And in every turn that used tools, call `show` once, right before `result`: one small picture that proves \
        what the turn made, found or decided, by the tool's rules. Bad news is worth showing too.
        """

    /// The `show` tool (documentation/design/screen-guide.md, "The show"):
    /// a result as a picture, which the Mac checks and shows in the popover.
    public static var showTool: [String: Any] { [
        "name": "show",
        "description": """
            Put one picture on the person's desk companion when your turn made, found or decided something. Call it \
            once, right before your final message, in every turn that used tools. Skip it only for a plain chat answer.

            headline: the conclusion in a few plain words, at most 28 characters: "search is 2.1x faster", not \
            "performance results".
            svg: one picture that proves the headline. Or image: an absolute path to a PNG you made, such as a \
            screenshot.
            link: optional. A URL or an absolute path to open on tap.

            Rules for the svg:
            - viewBox="0 0 420 190". The background is already dark; do not draw one.
            - It is read from a chair, on a small screen. One idea. At most 16 words. Text at least 14 px, lines at \
            least 3 px.
            - Use only these colors: ink #e8e6e0, dim #9aa0a8, good #5fae5a, bad #f08a6c, not checked #f0b56c, and \
            currentColor for your own accent.
            - Shapes, lines and text only. No gradients, filters, images, scripts, styles or outside links. At most 4 kB.
            - Show the bad news too: what failed, what you did not check.
            - Pick the form that fits: bars for a before and after, a row of boxes for a chain or a flow, two frames \
            for a visual change, a short check list for done and not done.
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "headline": ["type": "string", "description": "The conclusion in a few plain words (at most 28 characters)."],
                "svg": ["type": "string", "description": "One small SVG on viewBox 0 0 420 190, by the rules above."],
                "image": ["type": "string", "description": "Or an absolute path to a PNG you made."],
                "link": ["type": "string", "description": "A URL or an absolute path to open on tap."],
            ],
            "required": ["headline"],
        ] as [String: Any],
    ] }

    /// Opens what a result card links to, with `/usr/bin/open`: a web page
    /// in the browser; a file or folder shown in the Finder, never run or
    /// opened in an app. False when it isn't one of those or isn't there.
    @Sendable public static func open(_ link: String) -> Bool {
        guard let link = Card.openable(link) else { return false }
        var arguments = [link]
        if link.hasPrefix("/") || link.hasPrefix("~/") {
            let path = NSString(string: link).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return false }
            arguments = ["-R", path]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        return (try? process.run()) != nil
    }

    /// The line the tool server sends Boop for a card: its kind and its
    /// arguments as the card kept them, and the agent's process, so Boop
    /// finds the session. Boop holds it to the limits again as it reads it,
    /// since anything may write to the socket.
    public static func line(_ card: Card, process: AgentProcess?) -> Data {
        frame(["card": card.kind.rawValue, "args": card.args], process: process)
    }

    /// The line the tool server sends Boop for a show, as for a card.
    public static func line(_ show: Show, process: AgentProcess?) -> Data {
        frame(["show": show.args], process: process)
    }

    /// A show from a line `line(_:process:)` wrote, checked again, and its
    /// agent's process; nil for any other line or one that fails the check.
    public static func readShow(_ object: [String: Any]) -> (show: Show, process: AgentProcess?)? {
        guard let args = object["show"] as? [String: Any], let show = Show.make(args).show else { return nil }
        return (show, process(in: object))
    }

    /// A card from a line `line` wrote, and its agent's process; nil for
    /// any other line.
    public static func read(_ object: [String: Any]) -> (card: Card, process: AgentProcess?)? {
        guard let kind = (object["card"] as? String).flatMap(Card.Kind.init(rawValue:)),
              let card = Card.make(kind, object["args"] as? [String: Any] ?? [:],
                                   faces: Set(CharacterPack.active.faces.map(\.name))) else { return nil }
        return (card, process(in: object))
    }

    /// A line on the wire: `object` with the agent's process, as one line
    /// of JSON.
    private static func frame(_ object: [String: Any], process: AgentProcess?) -> Data {
        var object = object
        if let process { object["process"] = ["pid": Int(process.pid), "started": process.started] }
        return ((try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()) + Data("\n".utf8)
    }

    /// The agent's process a line names, if it names one.
    private static func process(in object: [String: Any]) -> AgentProcess? {
        let from = object["process"] as? [String: Any]
        return (from?["pid"] as? NSNumber).flatMap { pid in
            (from?["started"] as? NSNumber).map { AgentProcess(pid: pid.int32Value, started: $0.int64Value) }
        }
    }
}
