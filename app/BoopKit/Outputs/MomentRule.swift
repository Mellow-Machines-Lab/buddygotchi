import Foundation
import MellowHarness

/// What code decides of a Moment, so Jev is never asked: its move and its
/// size at every pass, and the whole Moment at your lock or unlock, a
/// working check-in and a boop from the world, which have no pass. Plain
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

    /// A quick win from this rung of its streak is a step bigger.
    public static let streakFrom = 3

    // MARK: The move

    /// The move a Moment plays at `e`, by its line's `facts`, or nil for
    /// just the face: a turn's finish by how it ended, the wake-up when
    /// you're back after `longAwayMs`, the notice when your prompt says
    /// the buddy's name.
    ///
    /// | The event | The move |
    /// | --- | --- |
    /// | A turn finished, failed | failure |
    /// | A turn finished, done, its last message giving up | failure |
    /// | A turn finished, done, its last message asking or only answering | reply |
    /// | A turn finished, done, in under a minute with no tool calls and no claim it's done | reply |
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
            case .reply: return "reply"
            case .stopped: return nil
            }
        }
        if e.type == .presence, e.phase == .end, (facts["away_ms"]?.int ?? 0) >= longAwayMs { return "wake up" }
        if e.type == .prompt, PromptReading(facts: e.data)?.named.isEmpty == false { return "notice" }
        return nil
    }

    /// How a finished turn ended, for the move and the size.
    enum Finish { case success, failure, reply, stopped }

    /// The finish a line's `facts` tell, or nil when they tell none: the
    /// turn's outcome, then what its last message's reading says.
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
            // Back-and-forth: nothing called, and over within the minute.
            let quick = Moment.turn(lengthMs: facts["length_ms"]?.int ?? 0) == 0
            return quick && (facts["tools"]?.int ?? 0) == 0 ? .reply : .success
        }
    }

    // MARK: The size

    /// How big a Moment at `e` is, by its line's `facts` and the lasting
    /// `mood`.
    ///
    /// | The event | The size |
    /// | --- | --- |
    /// | A finish | by its turn's length: small under 1 min, medium to 5 min, big from there |
    /// | … failed, hard-won (done after failed checks), or from the 3rd of a streak of quick wins | a step up, big at most |
    /// | … only a reply, stopped, or just after its fix; a win in a sad or cross mood | small |
    /// | Your words | medium |
    /// | A touch (a poke, a stroke, a shake…) | small |
    /// | Your prompt | medium when it sounds like something or says the buddy's name, else small |
    /// | You back | small; medium after an hour; big after a day |
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
            let streak = finish == .success
                && EventLine.rung(Int(facts["wins_in_a_row"]?.int ?? 0), of: EventLine.streak) >= streakFrom
            return finish == .failure || hardWon || streak ? min(big, tier + 1) : tier
        }
        switch e.type {
        case .said?: return medium
        case .prompt?:
            guard let r = PromptReading(facts: e.data) else { return small }
            return !r.named.isEmpty || (r.tone != nil && r.tone != .calm) ? medium : small
        case .presence?:
            let away = facts["away_ms"]?.int ?? 0
            return away >= daysMs ? big : away >= longAwayMs ? medium : small
        case .tool?:
            if facts["failing"] != nil { return medium }
            let before = facts["failed_before"]?.int ?? 0
            return before > 0 ? medium : small
        case .act?: return medium
        default: return small
        }
    }

    // MARK: Your lock and unlock

    /// What Boop does at your lock or unlock.
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

    /// The wave at your lock (`lock`) or unlock, `sinceLastMs` after the
    /// last lock (nil for the first), at `night` or not, with an agent
    /// `working` or not, in the lasting `mood`. An unlock that ends an
    /// away has no line, so it never gets here: the back's greeting plays.
    ///
    /// | When | The wave |
    /// | --- | --- |
    /// | The mood is cross | a snub |
    /// | A lock at night, no agent working | good night, and the nap |
    /// | A lock an hour or more after the last, or the first | a real wave |
    /// | Any other lock, and every unlock | a slight wave |
    public static func wave(lock: Bool, sinceLastMs: Int64?, night: Bool, working: Bool, mood: String?) -> Wave {
        if mood == cross { return .snub }
        guard lock else { return .slight }
        if night, !working { return .nap }
        return sinceLastMs.map { $0 >= lockWhileMs } ?? true ? .wave : .slight
    }

    // MARK: The working check-in

    /// The face and the word of a working check-in, the `rung`th of its
    /// round on the turn (from 1, of `EventLine.round`), whose latest
    /// `topic` is the agent's, with the mood's own resting `face`: a small
    /// Moment, never a sign. A sad, cross or lonely mood keeps its own
    /// face; any other is focused for the round's first half and
    /// determined for the rest. The word is about the tests when they're
    /// what the turn is at, else about the work.
    public static func checkIn(rung: Int, topic: String?, mood: String?, face: String) -> (face: String, say: String) {
        let own = mood == cross || mood == sad || mood == MoodOutput.missing
        return (own ? face : rung > EventLine.round / 2 ? "determined" : "focused", topic == "tests" ? "tests" : "work")
    }

    // MARK: A boop from the world

    /// The face and the size for another buddy's gesture of `kind`: warm
    /// and small, proud and medium for a cheer; cross, it softens to a
    /// curious look, small. A sign answers it either way (`Signs.world`),
    /// and it says how glad it is.
    public static func world(kind: String, mood: String?) -> (face: String, size: Int) {
        if mood == cross { return ("curious", small) }
        switch kind {
        case "cheer": return ("proud", medium)
        case "heart": return ("affectionate", small)
        default: return ("happy", small)
        }
    }
}
