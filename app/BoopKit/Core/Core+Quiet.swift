import Foundation
import MellowHarness

// Quiet for a while: "shh", the hush reply and the popover's button set
// Talk to quiet for half an hour, and then it's the setting's again. The
// core keeps only until when. Talking to Boop, the popover's button or
// choosing a Talk in Settings ends it sooner.
extension Core {
    /// How long "shh" keeps Boop quiet.
    public static let quietForMs: Int64 = 30 * 60_000

    /// Until when Boop is quiet for a while at `now`, or nil when Talk is
    /// the setting's.
    public func quietUntil(at now: Int64) -> Int64? {
        quietUntil.flatMap { now < $0 ? $0 : nil }
    }

    /// Talk as it stands at `now`: quiet for a while, else `setting`.
    public func talk(_ setting: Talk, at now: Int64) -> Talk {
        quietUntil(at: now) == nil ? setting : .quiet
    }

    /// Quiet for `ms` from `now`.
    public func quiet(forMs ms: Int64 = Core.quietForMs, at now: Int64) { quietUntil = now + ms }

    /// Talk is the setting's again.
    public func endQuiet() { quietUntil = nil }

    /// What a launch keeps of it: the hush reply that set it, and your
    /// next words, which end it.
    func replayQuiet(_ e: Event) {
        if e.type == .said { quietUntil = nil }
        if e.kind == Event.did, e.action == MomentOutput.outputName, e["ok"]?.bool == true, e["reply"]?.string == MomentOutput.hushReply {
            quietUntil = e.at + Self.quietForMs
        }
    }
}
