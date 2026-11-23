import Foundation

/// What an agent is told of Boop as its session starts (documentation/
/// design/brain.md, layer 2): who this Boop is, what it remembers of you,
/// and how it feels now, so the agent can offer it lines in its own voice.
/// Boop writes it in its state folder, beside the copy of `boop-cards` the
/// agents run, whenever it changes; the tool server reads it at `initialize`
/// and at each `status`. Off (Settings' "Your agent helps Boop think"), the
/// brief carries no memory and asks nothing.
public struct AgentBrief: Codable, Equatable, Sendable {
    public var name: String
    /// The personality's opening and its temperament, a few lines.
    public var personality: String
    /// The written memory's notes, You, Your work and You and Boop, never
    /// Recently's quotes of your words.
    public var memory: [String]
    /// The mood now, as a sentence: "Mochi is cross."
    public var mood: String
    /// Whether the agent is asked to help.
    public var on: Bool
    /// The pack's faces, which an offered line's feeling is one of.
    public var faces: [String]

    public init(name: String, personality: String, memory: [String], mood: String, on: Bool, faces: [String]) {
        self.faces = faces
        self.name = name
        self.personality = personality
        self.memory = memory
        self.mood = mood
        self.on = on
    }

    public static let file = "agent-brief.json"

    /// The brief beside `server`, the tool server's own path (the state
    /// folder's `bin/`), or at `BOOP_CARDS_BRIEF`.
    public static func read(server: String, environment: [String: String]) -> AgentBrief? {
        let url = environment["BOOP_CARDS_BRIEF"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: server).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentBrief.self, from: data)
    }

    public func write(to folder: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.file), options: .atomic)
    }

    /// The personality as the brief quotes it: the file's opening lines and
    /// its "At heart" sentence, comments left out.
    public static func personality(from steering: String) -> String {
        let text = steering.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        guard let body = ("\n" + text).components(separatedBy: "\nPERSONALITY\n").dropFirst().first else { return "" }
        let opening = body.split(separator: "\n").prefix(2).joined(separator: " ")
        let heart = body.components(separatedBy: "At heart").dropFirst().first?.components(separatedBy: "Where it").first
            .map { "At heart " + $0.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(240) } ?? ""
        return (opening + " " + heart).trimmingCharacters(in: .whitespaces)
    }

    /// What the server says, after the cards' own instructions: who Boop
    /// is, what it remembers, and the ask, with every argument named, since
    /// an agent may call a tool before it has read its schema.
    public var instructions: String {
        guard on else { return "" }
        let remembered = memory.isEmpty ? "" : " What \(name) remembers of the person: " + memory.joined(separator: " ")
        return """
             \(name) has a character of its own, and you can help it think. Who \(name) is: \(personality)\(remembered) \
            \(mood) The arguments, exactly: `status` takes `doing`, and `step`, `of` and `minutes_left` if you know them. \
            `result` takes `headline`, `detail` and `link`. On a turn that did real work, `result` may also take: \
            `boop_lines`, two objects {"says": "...", "feeling": "..."}, things \(name) might say about this turn in its \
            own voice, at most \(Card.saysMost) characters each, in different feelings, one of them doubtful (\(name) \
            picks one, or neither), each feeling one of \(faces.joined(separator: ", ")); \
            `you_seemed`, how the person seemed, one of \(Card.Seemed.allCases.map(\.rawValue).joined(separator: ", ")); \
            and `remember`, one plain sentence starting with You about the person or their work worth keeping, only if \
            there is one. \(name) is on the person's side, not yours: never make it praise your work. Leave all three out \
            on a quick answer, and never mention \(name) in your answer to the person.
            """
    }
}
