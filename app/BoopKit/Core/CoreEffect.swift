import AgentHooks
import Foundation
import MellowHarness
import LinkKit

/// What the core decided. The app hands each effect to the part that carries
/// it out: snapshots and the rules' reactions to the device link, what it
/// did by rule to the transcript, and a new day to the transcript's
/// pruning. The core itself never builds speech, writes files or talks to
/// the device: everything Boop says, and every face but the look and the
/// rules' reactions, is the brain's.
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// The session list changed but the snapshot didn't, as when a second
    /// idle session starts: only the popover and `debug.jsonl`'s `status`
    /// show it.
    case sessions
    /// What the rules did, as a `did`, or "needs you" as
    /// `needs_you_start` and `needs_you_end`, for the transcript:
    /// recorded after the event that caused it.
    case record(Event)
    /// The first activity of a new day: the transcript deletes its files
    /// past `Transcript.keptDays`.
    case newDay(date: String)
    /// Push-to-talk: turn the Mac's mic on or off, after `by`'s button.
    case listen(Bool, by: Core.Talker)
    /// A rule's reaction for the device, after the
    /// snapshot of the same input: `starting`, `stopped`, `error` or
    /// `helper_return`, or push-to-talk's `stop_listening`, which play only
    /// if nothing is playing on the device (`if_free`) and which no brain
    /// waits on; or push-to-talk's `listening` after the app's mic button, which
    /// plays at once (`BoopDevice.play`).
    case reaction(DeviceReaction)
    /// Open a thread on the Mac, in the app it runs in: a tap while
    /// something needs you.
    case open(ThreadRef)

    /// The effect on one line, for replays and debug mode.
    public var summary: String {
        switch self {
        case .state(let s): "state " + s.jsonLine
        case .sessions: "sessions"
        case .record(let e): "record " + e.summary
        case .newDay(let date): "new-day \(date)"
        case .listen(let on, let by): "listen \(on ? "on" : "off") (\(by.rawValue))"
        case .reaction(let m): "do " + JSONObject([("name", .string(m.name)), ("args", .object(m.args))]).json
        case .open(let t): "open \(t.agent) \(t.session)"
        }
    }
}
