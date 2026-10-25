import Foundation
import LinkKit
import MellowHarness

// The buddies: each board's link and reactions, and how the brain answers
// for each. One buddy runs as Boop always has: nothing names it.
extension Runtime {
    /// One buddy to run: who it is, its board, and its steering.
    public struct BuddyOptions {
        public var buddy: Buddy
        public var link: Transport?
        public var steering: Steering

        public init(buddy: Buddy, link: Transport?, steering: Steering) {
            self.buddy = buddy
            self.link = link
            self.steering = steering
        }
    }

    /// One buddy's board as it runs: its link, its reactions there and its
    /// mood. Its core is the pipeline's. On `home`.
    final class Rig: @unchecked Sendable {
        let buddy: Buddy
        /// Its tag in the transcript: its id with several buddies, nil for one.
        let tag: String?
        let link: DeviceLink
        let transport: Transport?
        let steering: Steering
        let reactions = Reactions()
        var mood: Choice!
        /// The newest snapshot sent to its board.
        var latest: StateSnapshot?
        /// The transport's `trouble` as the status last had it.
        var linkTrouble: TransportTrouble?

        init(_ options: BuddyOptions, tag: String?, log: @escaping (String) -> Void) {
            buddy = options.buddy
            self.tag = tag
            transport = options.link
            link = BoopDevice.link(options.link, log: log)
            steering = options.steering
        }
    }

    /// The rig of the buddy tagged `tag`, the first's for none.
    func rig(_ tag: String?) -> Rig { rigs.first { $0.tag == tag } ?? rigs[0] }

    /// A rig's core.
    func core(_ rig: Rig) -> Core { pipeline.core(rig.buddy.id) }

    /// Every buddy's board has said who it is: those with no link aside.
    public var helloFromEvery: Bool { rigs.allSatisfy { $0.transport == nil || $0.link.hello != nil } }

    /// ` left`: which buddy, for the log; nothing for the only one.
    static func whose(_ rig: Rig) -> String { rig.tag.map { " \($0)" } ?? "" }

    /// The buddies as MellowHarness's voices hear them: each event is
    /// answered by its own buddy first, then the others; a buddy's reaction
    /// by the others only.
    static func speakers(_ e: Event, _ buddies: [Buddy]) -> [String] {
        let ids = buddies.map(\.id)
        guard let own = e.buddy, ids.contains(own) else { return ids }
        let others = ids.filter { $0 != own }
        return e.type == .reacted ? others : [own] + others
    }

    /// One buddy's part of the brain: what `brain` registers for it.
    public struct Mind {
        public var buddy: Buddy
        public var steering: Steering
        public var personality: () -> Personality
        public var reactions: Reactions
        public var queue: (DeviceReaction, Pending) -> Void
        public var speaks: () -> Bool
        /// How much it says, chosen in Settings.
        public var talk: () -> Talk
        /// Writes a day's diary line, for the buddy that keeps one (the
        /// first, the one long-term.md set up); nil for none.
        public var diary: ((_ day: String, _ line: String) -> Void)?

        public init(buddy: Buddy, steering: Steering, personality: @escaping () -> Personality, reactions: Reactions,
                    queue: @escaping (DeviceReaction, Pending) -> Void, speaks: @escaping () -> Bool,
                    talk: @escaping () -> Talk = { .default }, diary: ((_ day: String, _ line: String) -> Void)? = nil) {
            self.diary = diary
            self.buddy = buddy
            self.steering = steering
            self.personality = personality
            self.reactions = reactions
            self.queue = queue
            self.speaks = speaks
            self.talk = talk
        }
    }

    /// Boop's brain on the pipeline's harness, the app's and the evals', so
    /// the two can't drift apart: for each buddy its outputs, mood then
    /// react, and the sections of Jev's state: the guide with how to read
    /// the rest, PERSONALITY, MOOD, and what how much it says adds (its
    /// `talk/` file, if any); then HISTORY, closed
    /// by how long the buddy has been in its mood and reaching back to the
    /// oldest working turn. With several buddies each is a voice: its own
    /// outputs and sections, and a prompt that opens with whom it answers
    /// for (`Buddy.header`). Returns each buddy's mood. The brain is the
    /// caller's to set (`harness.use`).
    public static func brain(_ pipeline: Pipeline, _ minds: [Mind]) -> [Choice] {
        let h = pipeline.harness, view = pipeline.view, all = pipeline.buddies
        if pipeline.several {
            for b in all { h.voice(Harness.Voice(id: b.id, name: b.name)) }
            h.speakers { e, _ in Runtime.speakers(e, all) }
        }
        let moods = minds.map { m -> Choice in
            let voice = pipeline.tag(m.buddy.id), pack = m.buddy.pack, core = pipeline.core(m.buddy.id)
            let mood = MoodOutput.choice(voice: voice, pack: pack)
            // A reaction your tap cut short is in progress while the pokes
            // go on, and done once anything else happens. A reaction's end,
            // MellowHarness's own event, never stops the pokes. The rule
            // holds the log, not the harness, which holds the rule.
            let transcript = h.log
            h.on("*") { e in
                guard !m.reactions.cutByTap.isEmpty, TranscriptView.stopsThePokes(e, transcript.view(before: e)) else { return }
                m.reactions.pokesStopped()
            }
            let react = ReactOutput(queue: m.queue, blocked: { core.reactionBlock }, who: { [weak h] now in
                // Weak: the harness holds this output.
                guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts),
                      let who = view.who(about: key, h.log.view(now: h.clock.now())) else { return nil }
                return DeviceReaction.Who(agent: who.agent, thread: who.thread, opens: who.opens)
            }, turnMs: { [weak h] now in
                // The finished turn's length, from its line's facts.
                guard let h, let now, case .int(let ms)? = h.line(now.seq)?.facts["length_ms"] else { return nil }
                return ms
            }, speaks: m.speaks, pack: pack, voice: voice, signs: m.steering.signs, calendar: { core.calendar(at: $0.at) },
            replies: m.steering.replies, status: { [weak h] said in
                // What this buddy's agents are up to as you ask, and how
                // each one's latest check or turn came out.
                guard let h, let words = said["words"]?.string else { return nil }
                let now = h.clock.now(), log = h.log.view(now: now)
                return StatusReply.answer(core.status(at: now, results: view.results(log), asked: view.asked(log)), words: words, at: now,
                                          stretchSince: core.stretchSince(at: now))
            }, moment: { core.moment(at: $0.at) })
            h.output(mood)
            h.output(react, openFor: ReactOutput.openForMs, keepOpen: TranscriptView.heldByPokes)
            if let write = m.diary, !m.steering.diary.isEmpty {
                h.output(DiaryOutput(templates: m.steering.diary, time: core.config.time, creature: m.buddy.name, voice: voice, write: write))
            }
            let mine = { (asked: Harness.Voice?) in asked?.id == voice }
            if voice != nil { h.section { _, v in mine(v) ? Buddy.header(for: m.buddy, among: all) : nil } }
            // The only buddy goes by the name you gave it, which the pack's
            // own words don't know.
            let own = CharacterPack.active.name
            let renamed = voice != nil || pack.name == own ? "" : "\n\(own) goes by \(pack.name) here: the name the person gave it."
            h.section { _, v in
                mine(v) ? m.steering.guide + renamed + "\n" + EventLine.reading(pack.name) + "\n" + EventLine.words(pack.name) : nil
            }
            h.section { _, v in mine(v) ? m.steering.personality(m.personality()).text : nil }
            h.section { log, v in mine(v) ? m.steering.mood(MoodOutput.value(mood, log), in: pack) : nil }
            // Last, so it outranks what PERSONALITY and MOOD say of words.
            h.section { _, v in mine(v) ? m.steering.talk(m.talk()) : nil }
            return mood
        }
        h.closing { _, now, log, v in
            let i = minds.firstIndex { pipeline.tag($0.buddy.id) == v?.id } ?? 0
            return MoodOutput.sinceLine(moods[i], log, at: now, name: minds[i].buddy.name)
        }
        h.reachBack { _, now, log in view.workingSince(at: now, log) }
        return moods
    }
}
