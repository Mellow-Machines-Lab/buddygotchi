import Foundation
import MellowHarness

/// What code decides of a Moment, so Jev is never asked: its move and its
/// size at every pass, your hello and your bye (`hello`, `bye`), and the
/// whole Moment at your lock or unlock, a working check-in and a boop from
/// the world, which have no pass. What it says is code's too (`Skits`).
/// Plain
/// functions of the event, its line's facts and the mood: the tables are
/// here and nowhere else (`MomentRuleTests` pins them).
public enum MomentRule {
    /// The sizes, as indexes into `MomentOutput.sizes`.
    public static let small = 0, medium = 1, big = 2

    /// The lasting moods the rules read by name, as `MoodOutput.missing`
    /// is: cross snubs you and softens for the world, and either keeps a
    /// win's finish small.
    public static let cross = "cross", sad = "sad"

    /// You back after this long gets the wake-up, and a medium moment;
    /// after `daysMs`, a big one.
    public static let longAwayMs: Int64 = 60 * 60_000
    public static let daysMs: Int64 = 24 * 60 * 60_000

    /// A quick win from this one in a row is a step bigger.
    public static let streakFrom = 3

    // MARK: The move

    /// The move a Moment plays at `e`, by its line's `facts`, or nil for
    /// just the face: a turn's finish by how it ended, a hello's (`hello`),
    /// the notice when your prompt says the buddy's name.
    ///
    /// | The event | The move |
    /// | --- | --- |
    /// | A turn finished, failed | failure |
    /// | A turn finished, done, its last message giving up | failure |
    /// | A turn finished, done, its last message asking or only answering | notice: a chat turn, a look up at you |
    /// | A turn finished, done, in under a minute with no tool calls and no claim it's done | notice: a chat turn, a look up at you |
    /// | A turn finished, done, whose calls only looked (reads, searches) and no claim it's done | notice: a chat turn, a look up at you |
    /// | Any other turn finished, done | success |
    /// | A turn stopped | none |
    /// | You back after an hour or more | wake up |
    /// | Your prompt saying the buddy's name | notice |
    /// | Anything else | none |
    public static func move(_ e: Event, facts: [String: JSONValue]) -> String? {
        if let finish = finish(facts) {
            switch finish {
            case .failure: return "failure"
            case .success: return "success"
            case .reply: return "notice"
            case .stopped: return nil
            }
        }
        if let move = hello(e, facts: facts, mood: nil)?.move { return move }
        if e.type == .prompt, PromptReading(facts: e.data)?.named.isEmpty == false { return "notice" }
        return nil
    }

    /// How a finished turn ended, for the move and the size. A reply, a
    /// chat turn, plays no finish and names no thread (`namesTurn`): Boop
    /// looks up at you once and holds "your turn" low, in the strip's place
    /// (`MomentOutput.yourTurn`).
    enum Finish { case success, failure, reply, stopped }

    /// The finish a line's `facts` tell, or nil when they tell none: the
    /// turn's outcome, then what its last message's reading says.
    /// Whether a finished turn's face names its thread on the board (the
    /// low sign and the rim's glow): every finish but a chat turn's.
    static func namesTurn(_ facts: [String: JSONValue]) -> Bool { finish(facts) != .reply }

    static func finish(_ facts: [String: JSONValue]) -> Finish? {
        guard let outcome = facts["outcome"]?.string else { return nil }
        if outcome == "failed" { return .failure }
        guard outcome == "done" else { return .stopped }
        let kind = (facts["message"]?.object?["kind"]?.string).flatMap(MessageText.Kind.init(rawValue:))
        switch kind {
        case .stuck?: return .failure
        case .question?, .answer?: return .reply
        case .done?: return .success
        case .other?, nil:
            // Back-and-forth: nothing called, and over within the minute;
            // or every call only looked, so the turn answered and made nothing.
            let quick = Moment.turn(lengthMs: facts["length_ms"]?.int ?? 0) == 0
            let tools = facts["tools"]?.int ?? 0
            let lookedOnly = tools > 0 && (facts["looks"]?.int ?? 0) == tools
            return (quick && tools == 0) || lookedOnly ? .reply : .success
        }
    }

    // MARK: The agent's line

    /// The faces that cheer: a line in one of them never plays at a finish
    /// that failed, nor while Boop is cross or sad.
    static let cheering: Set<String> = ["proud", "happy", "excited", "pleased", "amused", "affectionate", "mischievous"]

    /// Which of the lines an agent offered Boop says at its finish, or none
    /// (documentation/design/brain.md, layer 2): Boop's pick, not the
    /// agent's. A failed finish takes no cheering line; nor does a cross or
    /// sad Boop; a win with failed checks on the way leans to the doubtful
    /// line; else the line whose feeling is the face Boop shows, then the
    /// first that fits. A chat turn plays no finish, so it says nothing.
    public static func offeredLine(_ lines: [Card.Line], facts: [String: JSONValue], face: String, mood: String,
                                   room: Int) -> Card.Line? {
        guard let finish = finish(facts), finish == .success || finish == .failure else { return nil }
        var fits = lines.filter { $0.says.count <= room }
        if finish == .failure || mood == cross || mood == sad { fits.removeAll { cheering.contains($0.feeling) } }
        if finish == .success, (facts["checks_failed"]?.int ?? 0) > 0, let doubtful = fits.first(where: { !cheering.contains($0.feeling) }) {
            return doubtful
        }
        return fits.first { $0.feeling == face } ?? fits.first
    }

    // MARK: The size

    /// How big a Moment at `e` is, by its line's `facts` and the lasting
    /// `mood`.
    ///
    /// | The event | The size |
    /// | --- | --- |
    /// | A finish | by its turn's length: small under 1 min, medium to 5 min, big from there |
    /// | … failed, hard-won (done after failed checks), or from the 3rd quick win in a row | a step up, big at most |
    /// | … only a reply, stopped, or just after its fix; a win in a sad or cross mood | small |
    /// | Your words | medium |
    /// | A touch (a poke, a stroke, a shake…) | small |
    /// | Your prompt | medium when it sounds like something or says the buddy's name, else small |
    /// | A hello (`hello`) | small; medium after an hour away; big after a day |
    /// | A check failing | small; medium from the 2nd in a row |
    /// | A check passing after it failed, calls failing in a row, a push's result | medium |
    /// | Anything else (an idle check-in, an answered ask…) | small |
    public static func size(_ e: Event, facts: [String: JSONValue], mood: String?) -> Int {
        if let finish = finish(facts) {
            if finish == .stopped || finish == .reply || facts["reacted_to_fix"]?.bool == true { return small }
            // A win can't cheer a low mood up by itself (the gel's rule
            // too); a failure there is as big as any.
            if finish == .success, mood == sad || mood == cross { return small }
            let tier = min(big, Moment.turn(lengthMs: facts["length_ms"]?.int ?? 0))
            let hardWon = finish == .success && (facts["checks_failed"]?.int ?? 0) > 0
            let streak = finish == .success && (facts["wins_in_a_row"]?.int ?? 0) >= Int64(streakFrom)
            return finish == .failure || hardWon || streak ? min(big, tier + 1) : tier
        }
        if let hello = hello(e, facts: facts, mood: mood) { return hello.size }
        switch e.type {
        case .said?: return medium
        case .prompt?:
            guard let r = PromptReading(facts: e.data) else { return small }
            return !r.named.isEmpty || (r.tone != nil && r.tone != .calm) ? medium : small
        case .tool?:
            if facts["failing"] != nil { return medium }
            let before = facts["failed_before"]?.int ?? 0
            return before > 0 ? medium : small
        case .act?: return medium
        default: return small
        }
    }

    // MARK: You came or went: hello and bye

    /// The one thing a hello may add, the first that's there: the special
    /// day's sign; else the dream, told; else what happened while you were
    /// away, as a fact (CONTEXT's Noticed row, and the narration). The view
    /// picks it as it writes the hello's line (`TranscriptView.hello`).
    public enum Extra: Equatable, Sendable {
        case day(sign: String)
        case telling(tags: [String])
        case whileAway(String)

        /// The extra a line's `facts` carry, or nil for none.
        public init?(facts: [String: JSONValue]) {
            if let sign = facts[TranscriptView.daySignFact]?.string {
                self = .day(sign: sign)
            } else if case .array(let tags)? = facts["dream_tags"] {
                self = .telling(tags: tags.compactMap(\.string))
            } else if let noticed = facts[TranscriptView.noticedFact]?.string {
                self = .whileAway(noticed)
            } else {
                return nil
            }
        }
    }

    /// You came: what Boop's hello is.
    public struct Hello: Equatable, Sendable {
        /// How big it is.
        public var size: Int
        /// The move it plays (`MomentOutput.moves`), or nil for the face alone.
        public var move: String?
        /// At an unlock, its wave; nil when the brain picks the face.
        public var wave: Wave?
        /// Whether it plays whole (`Moment.greeting`): the first of Boop's
        /// day, or the one that tells the dream.
        public var whole: Bool
        public var extra: Extra?
        /// Whether Jev is asked: only after a real away (the presence
        /// detector's, 10 min or more), or where the hello is your touch,
        /// which has a pass of its own.
        public var asksJev: Bool
    }

    /// The hello at `e`, by its line's `facts` and the lasting `mood`, or
    /// nil when `e` isn't you coming.
    ///
    /// | You | The hello |
    /// | --- | --- |
    /// | unlock the Mac, not away | a slight wave, small, by rule; a snub when cross |
    /// | come back from an away | Jev's face and word: small; medium with the wake-up after an hour; big after a day |
    /// | touch it, the first you show up on Boop's day or with a dream to tell | the touch's own Moment, as a hello |
    ///
    /// The first of Boop's day, and one that tells the dream, plays whole.
    /// At most one extra comes with it (`Extra`).
    public static func hello(_ e: Event, facts: [String: JSONValue], mood: String?) -> Hello? {
        if e.type == .lock, e.phase == .end {
            return Hello(size: small, move: nil, wave: mood == cross ? .snub : .slight, whole: false, extra: nil, asksJev: false)
        }
        let extra = Extra(facts: facts)
        var whole = facts[TranscriptView.firstTodayFact] != nil
        if case .telling? = extra { whole = true }
        if e.type == .presence, e.phase == .end {
            let away = facts["away_ms"]?.int ?? 0
            return Hello(size: away >= daysMs ? big : away >= longAwayMs ? medium : small, move: away >= longAwayMs ? "wake up" : nil,
                         wave: nil, whole: whole, extra: extra, asksJev: true)
        }
        guard whole, Yours.touch(e) else { return nil }
        return Hello(size: small, move: nil, wave: nil, whole: true, extra: extra, asksJev: true)
    }

    /// You went: the bye at your lock of the Mac, `sinceLastMs` after the
    /// last lock (nil for the first), at `night` or not, with an agent
    /// `working` or not, in the lasting `mood`. Stepping away has none:
    /// nobody's there to see it.
    ///
    /// | When | The bye |
    /// | --- | --- |
    /// | The mood is cross | a snub |
    /// | At night, no agent working | good night, and the nap |
    /// | An hour or more after the last lock, or the first | a real wave |
    /// | Any other lock | a slight wave |
    public static func bye(sinceLastMs: Int64?, night: Bool, working: Bool, mood: String?) -> Wave {
        if mood == cross { return .snub }
        if night, !working { return .nap }
        return sinceLastMs.map { $0 >= lockWhileMs } ?? true ? .wave : .slight
    }

    /// How a hello or a bye waves.
    public enum Wave: Equatable, Sendable {
        /// Cross with you: its cross face, no wave, no word, no sign.
        case snub
        /// Routine: the slighter wave, small, in silence, no sign.
        case slight
        /// A first lock in a while: a real wave, medium, with a word and a sign.
        case wave
        /// A lock at night with nothing to watch: good night, a real wave,
        /// medium, with a word and a sign, and it sleeps at once.
        case nap
    }

    /// A lock this long after the last, or the first one, gets a real wave.
    public static let lockWhileMs = EventLine.lockWhileMs

    // MARK: The working check-in

    /// The face of a working check-in, the `rung`th of its round on the
    /// turn (from 1, of `EventLine.round`), with the mood's own resting
    /// `face`: a small Moment in silence, never a sign. A sad, cross or
    /// lonely mood keeps its own face; any other is focused for the round's
    /// first half and determined for the rest.
    public static func checkIn(rung: Int, mood: String?, face: String) -> String {
        let own = mood == cross || mood == sad || mood == MoodOutput.missing
        return own ? face : rung > EventLine.round / 2 ? "determined" : "focused"
    }

    // MARK: A boop from the world

    /// The face and the size for another buddy's gesture of `kind`: warm
    /// and small, proud and medium for a cheer; cross, it softens to a
    /// curious look, small. A sign answers it either way (`Signs.world`),
    /// in silence.
    public static func world(kind: String, mood: String?) -> (face: String, size: Int) {
        if mood == cross { return ("curious", small) }
        switch kind {
        case "cheer": return ("proud", medium)
        case "heart": return ("affectionate", small)
        default: return ("happy", small)
        }
    }
}
