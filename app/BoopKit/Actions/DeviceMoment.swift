import AgentHooks
import Foundation
import LinkKit

/// Something for the device to play, sent as a `do`: a
/// rule's one-shot is its animation; a brain reaction has a `say` and a
/// `mood`, its expression: the device draws that mood's version of the
/// look while it plays, and says the line in `say`, if there is one, over
/// it. With no animation it's a `react`; with one (task_complete,
/// reply_ready) it's the brain's finish. The rules' one-shots never carry
/// a mood. Whoever plays an animation or a face says how many `loops` of
/// its design. The finish for a thread's turn says `who`: the device names
/// it in the strip while the finish plays.
public struct DeviceMoment: Equatable, Sendable {
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

    /// What a brain reaction says: a line of up to two recorded takes (the
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

    /// The animation: a rule's one-shot, or the brain's finish; nil for a
    /// brain reaction with none, a `react`.
    public var anim: String?
    public var say: Say?
    public var mood: String?
    /// With an animation, how many times its design plays; with a `mood`
    /// and no animation, how many loops of the design it's drawn in the
    /// face holds. Nil sends none, which the device reads as 1.
    public var loops: Int?
    /// The animation's variation, from 1; nil sends none, and the device
    /// picks one for the moment's facts.
    public var variant: Int?
    /// With the finish, whose turn it was; nil sends none.
    public var who: Who?
    /// With task_complete, the turn's outcome: `success` or `failure`;
    /// the device plays a variation for it. Nil sends none.
    public var outcome: String?
    /// With starting, what started: `new_task`, `session`,
    /// `continuation` or `compacted`. Nil sends none.
    public var ctx: String?

    public init(anim: String? = nil, say: Say? = nil, mood: String? = nil, loops: Int? = nil,
                variant: Int? = nil, who: Who? = nil, outcome: String? = nil, ctx: String? = nil) {
        self.anim = anim
        self.say = say
        self.mood = mood
        self.loops = loops
        self.variant = variant
        self.who = who
        self.outcome = outcome
        self.ctx = ctx
    }

    /// The animations the device plays, each its design
    /// state's name, besides `listening`, which only push-to-talk plays
    /// (`BoopDevice.listening`).
    public static let anims = ["task_complete", "reply_ready", "starting", "helper_return",
                               "error", "stopped", "poked", "tap_spam"]
    /// A brain reaction with no animation: a line, a face, or both.
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
        if let variant { args["variant"] = .int(variant) }
        if let ctx { args["ctx"] = .string(ctx) }
        if let who { args["who"] = ["agent": .string(who.agent), "thread": .string(who.thread)] }
        if let say { args["say"] = say.json }
        if let mood { args["mood"] = .string(mood) }
        if let loops { args["loops"] = .int(loops) }
        return args
    }
    /// The logical mood is preserved in memory; old/pixel devices receive
    /// only names in their bank.
    public func args(for face: DeviceInfo.Face) -> JSONObject {
        var out = args
        if let mood { out["mood"] = .string(face == .gel ? mood : MoodGraph.pixelFallback(mood)) }
        return out
    }

}
