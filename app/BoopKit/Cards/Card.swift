import Foundation

/// A card an agent hands Boop to hold (plan/agent-cards.md): one main thing,
/// short enough to read from a chair, and at most one small line under it.
/// An agent sends one through the `boop-cards` tool server (`CardTool`); the
/// to-do card is Boop's own, from the hooks. A card's words are the
/// agent's: they go to the screen and never to the brain.
public struct Card: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
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

    /// A card from a tool call's arguments, held to the limits: text is one
    /// line, cut at a word where it can be; numbers outside their range and a
    /// link that isn't a web page or a path are left out. Nil with no text.
    public static func make(_ kind: Kind, _ args: [String: Any]) -> Card? {
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
        }
        return card
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
    public static let server = "boop"
    /// What the server tells the agent as it connects.
    public static let instructions = """
        Boop is a small desk companion with a screen that sits beside the person you're working for. It shows them what \
        you're doing, so they don't have to watch the terminal. In every turn that takes more than a couple of tool \
        calls: call `status` as you begin, and again each time you move to a different step; and call `result` once, \
        right before your final message, saying honestly how it went. Skip them only for a quick answer. Both return \
        at once and need no reply.
        """

    public static var tools: [[String: Any]] { [
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
                pull request, a preview page, a file), give its URL or path as `link`.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "headline": ["type": "string", "description": "The outcome in a few plain words (at most 24 characters)."],
                    "detail": ["type": "string", "description": "One more short line (at most 28 characters)."],
                    "link": ["type": "string", "description": "A URL or file path the person can open to see the result."],
                ],
                "required": ["headline"],
            ] as [String: Any],
        ],
    ] }

    /// A card that came over the socket, back as a tool call's arguments,
    /// so `Card.make` holds it to the limits once more.
    static func arguments(_ card: [String: Any]) -> [String: Any] {
        var args = card
        args["doing"] = card["text"]
        args["headline"] = card["text"]
        args["minutes_left"] = card["minutes"]
        return args
    }

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

    /// The line the tool server sends Boop for a card: the card, which
    /// agent's tool it is and that agent's process, so Boop finds the session.
    public static func line(_ card: Card, agent: String?, pid: Int32?, started: Int64?) -> Data {
        var object: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(card), let c = try? JSONSerialization.jsonObject(with: data) { object["card"] = c }
        if let agent { object["agent"] = agent }
        if let pid, let started { object["process"] = ["pid": Int(pid), "started": started] }
        return ((try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()) + Data("\n".utf8)
    }
}
