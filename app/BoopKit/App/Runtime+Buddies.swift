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
        public var reactions: Reactions
        public var queue: (Moment, Pending) -> Void
        public var speaks: () -> Bool
        /// How much it says, chosen in Settings.
        public var talk: () -> Talk
        /// Carries out the core's effects an output's choice caused (a hush):
        /// the app's show on the board; nil logs their records only.
        public var effects: (([CoreEffect]) -> Void)?
        /// MEMORY, the written memory as Jev reads it, or nil for none.
        public var memory: () -> String?
        /// The questions it may ask at an event, of the pack's, in its mood
        /// (`Asks.askable`); and the answers kept as tags at a time, for
        /// every sign's lines.
        public var askable: (Event, LogView, [Asks.Question], Choice) -> [Asks.Question]
        public var answerTags: (Int64) -> [String]
        /// Your company and the day so far, the memory reader's open day,
        /// for CONTEXT; nil with no memory.
        public var company: () -> MemoryReader.Tallies?
        /// Whether you've met a kind of wish once, kept with the memory:
        /// until then it shows how.
        public var wishDone: (Core.WishKind) -> Bool
        /// What its picks of words start from: a launch's own, so no two
        /// launches say the same order. Evals give theirs.
        public var seed = Mind.launchSeed()
        /// What it may bring up about you at a time (`Memory.felt`).
        public var felt: (Int64) -> [Memory.Felt] = { _ in [] }
        /// What it notices from, or nil for a buddy that doesn't: the days
        /// kept, when each notice last played, and whether a thread had a
        /// turn since the last dream (`Memory`).
        public var noticing: Noticing?
        public struct Noticing {
            public var digests: () -> [DayDigest]
            public var shown: () -> [String: Int64]
            public var onLately: (String) -> Bool

            public init(digests: @escaping () -> [DayDigest], shown: @escaping () -> [String: Int64], onLately: @escaping (String) -> Bool) {
                self.digests = digests
                self.shown = shown
                self.onLately = onLately
            }
        }
        public static func launchSeed() -> UInt64 { .random(in: .min ... .max) }

        public init(buddy: Buddy, steering: Steering, reactions: Reactions,
                    queue: @escaping (Moment, Pending) -> Void, speaks: @escaping () -> Bool,
                    talk: @escaping () -> Talk = { .default }, effects: (([CoreEffect]) -> Void)? = nil,
                    memory: @escaping () -> String? = { nil },
                    askable: @escaping (Event, LogView, [Asks.Question], Choice) -> [Asks.Question] = { _, _, _, _ in [] },
                    answerTags: @escaping (Int64) -> [String] = { _ in [] },
                    company: @escaping () -> MemoryReader.Tallies? = { nil },
                    wishDone: @escaping (Core.WishKind) -> Bool = { _ in false }) {
            self.memory = memory
            self.wishDone = wishDone
            self.company = company
            self.askable = askable
            self.answerTags = answerTags
            self.effects = effects
            self.buddy = buddy
            self.steering = steering
            self.reactions = reactions
            self.queue = queue
            self.speaks = speaks
            self.talk = talk
        }
    }

    /// Boop's brain on the pipeline's harness, the app's and the evals', so
    /// the two can't drift apart: for each buddy its outputs, mood then
    /// react, and the sections of Jev's state: the guide with how to read
    /// the rest, PERSONALITY, MEMORY, MOOD and CONTEXT (how things stand,
    /// the talk setting among it); then HISTORY, closed
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
            for kind in Core.WishKind.allCases { core.wishMetSigns[kind] = Asks.wishMetSign(m.steering.asks, kind) }
            core.wishDone = m.wishDone
            let mood = MoodOutput.choice(voice: voice, pack: pack)
            // What it notices, read by the output and CONTEXT alike: none on
            // Quiet, none when it couldn't start anything of its own, and none
            // with no lines for it. An open wish holds up all but `waiting`.
            let noticeAt = { (about: Event, log: LogView) -> Notices.Notice? in
                guard let noticing = m.noticing, MomentOutput.isCheckIn(about), m.talk() != .quiet, core.mayBeOwnBeat(at: about.at) else { return nil }
                var moment = Notices.Moment(at: about.at, wall: core.wall(about.at), time: core.config.time)
                moment.agents = core.status(at: about.at, results: [:])
                moment.hereSince = m.company()?.hereSince
                moment.dozing = core.dozes(at: about.at)
                moment.wishOpen = core.wish != nil
                (moment.failures, moment.sharpAt) = view.rough(log)
                moment.digests = noticing.digests()
                moment.shown = noticing.shown()
                return Notices.due(moment).flatMap { n in
                    Signs.notice(m.steering.signs, n.kind.rawValue, agent: n.agent).isEmpty ? nil : n
                }
            }
            // What's noticed at NOW's own moment: your coming back's, in its
            // line; your first prompt today on a thread you'd left.
            let noticedAt = { (about: Event, line: Line?) -> String? in
                if let said = line?.facts[TranscriptView.noticedFact]?.string { return said }
                guard let noticing = m.noticing, about.type == .prompt, line?.facts[TranscriptView.firstHereTodayFact] != nil,
                      let thread = line?.facts["thread"]?.object else { return nil }
                guard let key = thread["workspace"]?.string ?? thread["project"]?.string else { return nil }
                return Notices.backOn(key, digests: noticing.digests(), known: noticing.onLately(key), at: core.wall(about.at), time: core.config.time)
            }
            let wishWhy = { (at: Int64) -> String? in
                guard let noticing = m.noticing else { return nil }
                return Notices.wishReason(today: m.company(), digests: noticing.digests(),
                                          daysOld: core.dayCount(at: at), at: core.wall(at), time: core.config.time)
            }
            // A reaction your tap cut short is in progress while the pokes
            // go on, and done once anything else happens. A reaction's end,
            // MellowHarness's own event, never stops the pokes. The rule
            // holds the log, not the harness, which holds the rule.
            let transcript = h.log
            h.on("*") { e in
                guard !m.reactions.cutByTap.isEmpty, TranscriptView.stopsThePokes(e, transcript.view(before: e)) else { return }
                m.reactions.pokesStopped()
            }
            // What an output's own act comes to, carried out.
            let carryOut = { [weak pipeline] (fx: [CoreEffect], at: Int64) in
                if let effects = m.effects { effects(fx) } else { pipeline?.effects(fx, buddy: voice, at: at) }
            }
            let react = MomentOutput(queue: m.queue, blocked: { core.reactionBlock }, replyBlocked: { core.replyBlock }, who: { [weak h] now in
                // Weak: the harness holds this output.
                guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts),
                      let who = view.who(about: key, h.log.view(now: h.clock.now())) else { return nil }
                return Moment.Who(agent: who.agent, thread: who.thread, opens: who.opens)
            }, turnMs: { [weak h] now in
                // The finished turn's length, from its line's facts.
                guard let h, let now, case .int(let ms)? = h.line(now.seq)?.facts["length_ms"] else { return nil }
                return ms
            }, speaks: m.speaks, pack: pack, voice: voice, signs: m.steering.signs,
            calendar: { core.calendar(at: $0.at) + m.answerTags($0.at) },
            replies: m.steering.replies, status: { [weak h] said in
                // What this buddy's agents are up to as you ask, and how
                // each one's latest check or turn came out.
                guard let h, let words = said["words"]?.string else { return nil }
                let now = h.clock.now(), log = h.log.view(now: now)
                return StatusReply.answer(core.status(at: now, results: view.results(log), asked: view.asked(log)), words: words, at: now,
                                          stretchSince: core.stretchSince(at: now))
            }, moment: { core.moment(at: $0.at) }, hushed: { core.hushed(at: $0) != nil }, hush: { ms, at in
                // What you said hushed it, or let it talk again.
                carryOut(ms.map { core.hush(forMs: $0, by: .talk, at: at) } ?? core.unhush(by: .talk, at: at), at)
            }, nap: { at in
                carryOut(core.nap(at: at), at)
            }, talk: m.talk, reason: { [weak h] about in
                // Why, from the line the brain read for it. Weak: the
                // harness holds this output.
                guard let h, let about else { return nil }
                // A check-in over a wish left an hour or more: that's why.
                if about.type == .checkIn, let w = core.wish, w.waitedMs >= 60 * 60_000 {
                    let span = ContextSection.span(w.waitedMs)
                    return Narration(cause: "\(pack.name) wished for \(w.kind.words) \(span) ago.", fact: "wish: \(span)")
                }
                let line = h.line(about.seq)
                let why = Narration.of(about, line: line, untouchedMs: ContextSection.untouchedMs(m.company(), at: h.clock.now()),
                                       name: pack.name)
                // Your goodnight says the day's turns, on the board too.
                if about.type == .lock, about.phase == .start, core.calendar(at: about.at).contains("night"),
                   let turns = Notices.goodnight(turns: m.company()?.turns ?? 0), let why {
                    return Narration(cause: why.cause + " " + turns, fact: String(turns.dropLast()))
                }
                let noted = why?.noting(noticedAt(about, line))
                // The morning's caption keeps to the day and the dream.
                guard line?.facts[TranscriptView.firstTodayFact] != nil, let days = core.dayCount(at: about.at) else { return noted }
                return Narration.day(days, leading: noted)
            }, moodMoved: { [mood] now, log in
                MoodOutput.boardFact(mood, log, now: now, pack: pack)
            }, note: { fact, at in
                carryOut([.reaction(Moment(reason: fact))], at)
            }, dreams: m.steering.dreams, line: { [weak h] about in h?.line(about.seq) },
            occasion: { at in core.dayGreeting(at: at) }, asks: m.steering.asks, askable: { [mood] about, log, questions in m.askable(about, log, questions, mood) },
            wishable: { [mood] about, log in
                // At an ask's moment, within the core's caps.
                Asks.moment(about, log, mood: mood, untouchedMs: ContextSection.untouchedMs(m.company(), at: about.at)).isEmpty
                    ? [] : core.wishable(at: about.at)
            }, makeWish: { kind, at in
                carryOut(core.makeWish(kind, at: at), at)
            }, wishDone: m.wishDone,
            dayNumber: { LocalTime.dayNumber(core.config.time.boopDay(core.wall($0))) ?? 0 },
            moodFace: { [mood] log in MoodOutput.value(mood, log) },
            today: m.company, felt: m.felt, notice: noticeAt, wishWhy: wishWhy, seed: m.seed)
            h.output(mood)
            h.output(react, openFor: MomentOutput.openForMs, keepOpen: TranscriptView.heldByPokes)
            let mine = { (asked: Harness.Voice?) in asked?.id == voice }
            if voice != nil { h.section { _, v in mine(v) ? Buddy.header(for: m.buddy, among: all) : nil } }
            // The only buddy goes by the name you gave it, which the pack's
            // own words don't know.
            let own = CharacterPack.active.name
            let renamed = voice != nil || pack.name == own ? "" : "\n\(own) goes by \(pack.name) here: the name the person gave it."
            h.section { _, v in
                mine(v) ? m.steering.guide + renamed + "\n" + EventLine.reading(pack.name) + "\n" + EventLine.words(pack.name) : nil
            }
            h.section { _, v in mine(v) ? m.steering.personality.text : nil }
            // What it remembers, after who it is and before how it feels.
            h.section { _, v in mine(v) ? m.memory() : nil }
            h.section { log, v in mine(v) ? m.steering.mood(MoodOutput.value(mood, log), in: pack) : nil }
            // How things stand: when it is, the talk setting, the buddy,
            // you, the agents, the day so far. Last before HISTORY.
            h.section { [weak h] log, v in
                guard mine(v), let h else { return nil }
                let now = h.clock.now()
                // NOW is an idle check-in when one is the newest thing to happen.
                let newest = log.events.last { !$0.fromHarness }
                let idle = newest.map(MomentOutput.isCheckIn) == true
                let stage = Growth.stages[max(1, min(core.stage(), Growth.stages.count)) - 1].name
                let wall = core.wall(now), time = core.config.time
                let buddy = ContextSection.Buddy(stage: stage, daysOld: core.config.hatched.map { time.days(from: $0, to: wall) })
                let when = ContextSection.when(at: wall, specialDays: Days.words(at: wall, hatched: core.config.hatched, name: pack.name,
                                                                                    stage: core.config.stageReached, time: time),
                                               time: time)
                return ContextSection.section(when: when, talk: m.talk(), silentMs: core.hushed(at: now).map { $0.until - now },
                                              buddy: buddy, company: m.company(),
                                              agents: core.status(at: now, results: [:]),
                                              wish: core.wishRow(at: now, name: pack.name, idle: idle, because: idle ? wishWhy(now) : nil),
                                              wishToday: core.wishToday(at: now, name: pack.name),
                                              noticed: newest.flatMap { e in noticedAt(e, h.line(e.seq)) ?? noticeAt(e, log).map { $0.fact + "." } },
                                              at: now, name: pack.name)
            }
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
