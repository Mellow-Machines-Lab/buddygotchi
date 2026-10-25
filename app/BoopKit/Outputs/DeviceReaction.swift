import AgentHooks
import Foundation
import LinkKit

/// A reaction for the device to play, sent as a `do`: a
/// rule's reaction is its animation; a brain reaction has a `say` and a
/// `mood`, its expression: the device draws that mood's version of the
/// look while it plays, and says the takes in `say`, if there are any,
/// over it. With no animation it's a `react`; with one it's the brain's
/// finish (task_complete, reply_ready), its wake_up (you back after a
/// long break) or its notice (its name in your prompt). The rules'
/// reactions never carry
/// a mood. Whoever plays an animation or a face says how many `loops` of
/// its design. The finish for a thread's turn, or a face for it, says
/// `who`: the device names it in the strip, and marks it on the face, while
/// it plays and for a moment after.
public struct DeviceReaction: Equatable, Sendable {
    /// The agent and thread the finish is for.
    public struct Who: Equatable, Sendable {
        /// `claude` or `codex`.
        public var agent: String
        /// The thread's name, cut as `StateSnapshot.clip` cuts names.
        public var thread: String
        /// Where a tap on the finish opens the thread.
        /// Not sent: the device's tap names the finish's `do` id instead.
        public var opens: ThreadRef?

        public init(agent: String, thread: String, opens: ThreadRef? = nil) {
            self.agent = agent
            self.thread = StateSnapshot.clip(thread, marked: true)
            self.opens = opens
        }
    }

    /// What a brain reaction says: up to two recorded takes (the
    /// feeling's, then the topic's), or nothing. A reaction
    /// always has one, even with no take: it's the reply that ends
    /// push-to-talk's `listening`.
    public struct Say: Equatable, Sendable {
        public var takes: [Take]

        public init(takes: [Take]) {
            self.takes = Array(takes.prefix(2))
        }

        /// The `say` object: `{"take":"new.d02"}`, with its second take as
        /// `then`, or `{}`.
        public var json: JSON {
            var say = JSONObject()
            if let first = takes.first { say["take"] = .string(first.id) }
            if takes.count > 1 { say["then"] = .string(takes[1].id) }
            return .object(say)
        }

        /// What the bubble shows, and HISTORY reads: the takes' words.
        public var text: String? { takes.isEmpty ? nil : takes.map(\.text).joined(separator: " ") }
    }

    /// The animation: a rule's reaction, or the brain's finish, wake_up or notice;
    /// nil for a brain reaction with none, a `react`.
    public var anim: String?
    public var say: Say?
    public var mood: String?
    /// With an animation, how many times its design plays; with a `mood`
    /// and no animation, how many loops of the design it's drawn in the
    /// face holds. Nil sends none, which the device reads as 1.
    public var loops: Int?
    /// With the finish, or a face for a finished turn, whose turn it was;
    /// nil sends none.
    public var who: Who?
    /// With task_complete, the turn's outcome: `success` or `failure`;
    /// the device plays a variation for it. Nil sends none.
    public var outcome: String?
    /// With task_complete, the tier its turn reached (`turn(lengthMs:)`),
    /// which the device may size the finish by. Nil sends none.
    public var turn: Int?
    /// The variation to play, from 1, when one is wanted; nil sends none,
    /// and the device picks.
    public var variant: Int?
    /// With starting, what started: `new_task`, `session`,
    /// `continuation` or `compacted`. Nil sends none.
    public var ctx: String?
    /// What the buddy holds up on a sign while it plays (`Signs`); nil
    /// for none.
    public var sign: String?
    /// With a brain reaction to what you said, its reply
    /// (`ReactOutput.Reply`): the board plays its pack's clip for it
    /// over the face. Nil sends none.
    public var reply: String?

    public init(anim: String? = nil, say: Say? = nil, mood: String? = nil, loops: Int? = nil,
                who: Who? = nil, outcome: String? = nil, turn: Int? = nil, variant: Int? = nil,
                ctx: String? = nil, sign: String? = nil) {
        self.anim = anim
        self.say = say
        self.mood = mood
        self.loops = loops
        self.who = who
        self.outcome = outcome
        self.turn = turn
        self.variant = variant
        self.ctx = ctx
        self.sign = sign
    }

    /// A finished turn's length as a finish's `turn`: the tier it reached,
    /// as the tags count them (`Occasions.tiers`), from 1 for `tier1` to 5
    /// for `tier5`, and 0 short of the first.
    public static func turn(lengthMs: Int64) -> Int {
        Occasions.tiers.lastIndex { lengthMs >= $0.fromMs }.map { $0 + 1 } ?? 0
    }

    /// The animations the Mac asks the device to play, each its design
    /// state's name, besides `listening`, which only push-to-talk plays
    /// (`BoopDevice.listening`). A tap's `poked` and `tap_spam` the device
    /// plays itself.
    public static let anims = ["task_complete", "reply_ready", "wake_up", "notice", "starting", "helper_return", "stopped"]
    /// A brain reaction with no animation: takes, a face, or both.
    public static let react = "react"

    /// The most `loops` the device plays (firmware `Behaviour::kMaxLoops`).
    public static let maxLoops = 6

    /// The `do`'s name: its animation, or `react`.
    public var name: String { anim ?? Self.react }

    /// The `do`'s `args`, in the order the protocol's
    /// examples give them. Every string is escaped as JSON.
    public var args: JSONObject {
        var args = JSONObject()
        if let outcome { args["outcome"] = .string(outcome) }
        if let turn { args["turn"] = .int(turn) }
        if let variant { args["variant"] = .int(variant) }
        if let ctx { args["ctx"] = .string(ctx) }
        if let sign { args["sign"] = .string(sign) }
        if let reply { args["reply"] = .string(reply) }
        if let who { args["who"] = ["agent": .string(who.agent), "thread": .string(who.thread)] }
        if let say { args["say"] = say.json }
        if let mood { args["mood"] = .string(mood) }
        if let loops { args["loops"] = .int(loops) }
        return args
    }
}
