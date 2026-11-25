import Foundation
import LinkKit
import MellowHarness

// The buddy's board as it runs, and the brain's part for it.
extension Runtime {
    /// The board as it runs: its link, its reactions there and the
    /// buddy's mood. Its core is the pipeline's. On `home`.
    final class Rig: @unchecked Sendable {
        let link: DeviceLink
        let transport: Transport?
        let steering: Steering
        let reactions = Reactions()
        var mood: Choice!
        /// The newest snapshot sent to its board.
        var latest: StateSnapshot?
        /// The transport's `trouble` as the status last had it.
        var linkTrouble: TransportTrouble?

        init(link: Transport?, steering: Steering, log: @escaping (String) -> Void) {
            transport = link
            self.link = BoopDevice.link(link, log: log)
            self.steering = steering
        }
    }

    /// The buddy's part of the brain: what `brain` registers for it.
    public struct Mind {
        public var buddy: Buddy
        public var steering: Steering
        public var reactions: Reactions
        public var queue: (Moment, Pending) -> Void
        public var speaks: () -> Bool
        /// How much it says, chosen in Settings; `brain` makes it quiet
        /// while the core says so (`Core.quiet`).
        public var talk: () -> Talk
        /// Whether it may swear (`AppSettings.swearing`): on unless told,
        /// as the evals keep it.
        public var swears: () -> Bool = { true }
        /// Carries out the core's effects an output's choice caused (a wish, a nap):
        /// the app's show on the board; nil logs their records only.
        public var effects: (([CoreEffect]) -> Void)?
        /// MEMORY, the written memory as Jev reads it, or nil for none.
        public var memory: () -> String?
        /// The questions due at a time, of the pack's (`Asks.due`); and the
        /// answers kept as tags at a time, for every sign's lines.
        public var askable: (Int64, [Asks.Question]) -> [Asks.Question]
        public var answerTags: (Int64) -> [String]
        /// Your company and the day so far, the memory reader's open day,
        /// for CONTEXT; nil with no memory.
        public var company: () -> MemoryReader.Tallies?
        /// What its picks of words start from: a launch's own, so no two
        /// launches say the same order. Evals give theirs.
        public var seed = Mind.launchSeed()
        /// What the event of a `seq` earned (`GrowthStore.earned`), for its
        /// moment's sign.
        public var earned: (Int) -> (source: Growth.Source, xp: Int)? = { _ in nil }
        /// What it may bring up about you at a time (`Memory.felt`).
        public var felt: (Int64) -> [Memory.Felt] = { _ in [] }
        /// How long a line the board holds low: the gel's low sign's room,
        /// or a plain sign's on a face that holds nothing low.
        public var lineRoom: () -> Int = { MemoryPipeline.signMax }
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
                    askable: @escaping (Int64, [Asks.Question]) -> [Asks.Question] = { _, _ in [] },
                    answerTags: @escaping (Int64) -> [String] = { _ in [] },
                    company: @escaping () -> MemoryReader.Tallies? = { nil }) {
            self.memory = memory
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

    /// What code does to the mood, never Jev: a levelled mood's level,
    /// counted from what provokes it (`MoodOutput.provocation`), and every
    /// mood's fade on the harness's clock (`MoodOutput.fade`). Each is a
    /// change of the mood in the transcript, by `rule`.
    static func moodRules(_ mood: Choice, on h: Harness, view: TranscriptView, pack: CharacterPack) {
        let levels = { (id: String) in pack.lasting(id).flatMap { $0.levelled ? $0.faces.count : nil } }
        let step = { [weak h] (to: Int, about: Event?, log: LogView) in
            guard let h, let result = MoodOutput.levelled(mood, to: to, log: log, pack: pack) else { return }
            h.did(result.message, for: about, action: mood.name, facts: result.facts)
        }
        // When each hold was last so: a fade's clock starts again from it.
        var heldAt: [CharacterPack.Fade.Hold: Int64] = [:]
        let hold = { [weak h] (now: Int64, e: Event?) in
            guard let h else { return }
            if view.isWorking(at: now, h.log.view(now: now)) || (e?.type == .turn && e?.phase == .end) { heldAt[.working] = now }
            if view.away || (e?.type == .presence && e?.phase == .end) { heldAt[.away] = now }
        }
        h.on("*") { [weak h] e in
            guard let h else { return }
            let log = h.log.view(now: e.at)
            hold(e.at, e)
            if e.kind == Event.did {
                guard e["ok"]?.bool == true, e["by"]?.string != "rule" else { return }
                let about = e.about.flatMap { log.event($0) }
                // Entering a levelled mood: as cross as what caused it.
                if e.action == mood.name, e["level"] == nil, let to = e["to"]?.string, to != e["from"]?.string, let count = levels(to),
                   let about, let by = h.line(about.seq).flatMap({ MoodOutput.provocation(about, facts: $0.facts) }) {
                    step(MoodOutput.provoked(nil, by: by, of: count), about, log)
                }
                // Rude words, as its reply says they were, provoke it too.
                if e.action == MomentOutput.outputName, e["reply"]?.string == MomentOutput.rudeReply,
                   let count = levels(MoodOutput.value(mood, log, pack: pack)) {
                    step(MoodOutput.provoked(MoodOutput.level(mood, log), by: 1, of: count), about, log)
                }
                return
            }
            // In a levelled mood, what provokes it takes it a level up, and
            // a gentle touch a level down.
            guard let count = levels(MoodOutput.value(mood, log, pack: pack)) else { return }
            if Touch(e)?.soothes == true { return step(MoodOutput.soothed(MoodOutput.level(mood, log)), e, log) }
            guard let by = h.line(e.seq).flatMap({ MoodOutput.provocation(e, facts: $0.facts) }) else { return }
            step(MoodOutput.provoked(MoodOutput.level(mood, log), by: by, of: count), e, log)
        }
        h.tick { [weak h] now, log in
            hold(now, nil)
            if let h, let result = MoodOutput.fade(mood, log, at: now, pack: pack, heldAt: { heldAt[$0] }) {
                h.did(result.message, for: nil, action: mood.name, facts: result.facts)
            }
            return nil
        }
    }

    /// Boop's brain on the pipeline's harness, the app's and the evals', so
    /// the two can't drift apart: its outputs, mood then react, and the
    /// sections of Jev's state: the guide with how to read the rest,
    /// PERSONALITY, MEMORY, MOOD and CONTEXT (how things stand, the talk
    /// setting among it); then HISTORY, closed by how long the buddy has
    /// been in its mood and reaching back to the oldest working turn.
    /// Returns the mood. The brain is the caller's to set (`harness.use`).
    public static func brain(_ pipeline: Pipeline, _ m: Mind) -> Choice {
        let h = pipeline.harness, view = pipeline.view, pack = m.buddy.pack, core = pipeline.core
        for kind in Core.WishKind.allCases { core.wishMetSigns[kind] = Asks.wishMetSign(m.steering.asks, kind) }
        // Missing you is offered only when it may begin: no agent working,
        // and you back after about a day.
        let mood = MoodOutput.choice(pack: pack) { [weak h] now, log in
            MoodOutput.mayMiss(now, facts: now.flatMap { h?.line($0.seq)?.facts }, working: view.isWorking(at: h?.clock.now() ?? 0, log))
        }
        moodRules(mood, on: h, view: view, pack: pack)
        // Talk as it stands: quiet for a while, else the setting.
        let talk = { [weak h] in core.talk(m.talk(), at: h?.clock.now() ?? 0) }
        // The idle beat: the one thing Boop may hold up at an idle
        // check-in, dealt in `IdleBeat.Kind`'s order under its one cap.
        // None when it couldn't start anything of its own.
        let idleBeat = { (about: Event, log: LogView, forced: Bool) -> [IdleBeat.Candidate] in
            let now = about.at, wall = core.wall(about.at), time = core.config.time
            guard MomentOutput.isCheckIn(about), core.mayBeOwnBeat(at: now) else { return [] }
            let room = IdleBeat.room(IdleBeat.shownAt(log), now: now, sameDay: { time.boopDay(core.wall($0)) == time.boopDay(wall) })
            // Dozed off, it wants and asks nothing: only the notice that
            // it's late comes then (`Notices.dueOther`).
            let dozing = core.dozes(at: now)
            let noticed = { (find: (Notices.Moment) -> Notices.Notice?, kind: IdleBeat.Kind) -> IdleBeat.Candidate? in
                guard let noticing = m.noticing else { return nil }
                var moment = Notices.Moment(at: now, wall: wall, time: time)
                moment.agents = core.status(at: now, results: [:])
                moment.hereSince = m.company()?.hereSince
                moment.dozing = dozing
                (moment.failures, moment.sharpAt) = view.rough(log)
                moment.digests = noticing.digests()
                moment.shown = noticing.shown()
                return find(moment).map { IdleBeat.Candidate(kind, signs: Signs.notice(m.steering.signs, $0.kind.rawValue, agent: $0.agent), notice: $0) }
            }
            let tags = core.calendar(at: now) + m.answerTags(now)
            let offer = { (kind: IdleBeat.Kind) -> IdleBeat.Candidate? in
                if dozing, !forced, kind != .waiting, kind != .notice { return nil }
                switch kind {
                case .waiting: return noticed(Notices.dueWaiting, .waiting)
                case .notice: return noticed(Notices.dueOther, .notice)
                case .wish:
                    // One a Boop day, never while it's cross, of the kinds
                    // it may want now, taking turns by the day.
                    let kinds = core.wishable(at: now), day = LocalTime.dayNumber(time.boopDay(wall)) ?? 0
                    guard !core.wishedToday(at: now), !kinds.isEmpty, MoodOutput.value(mood, log, pack: pack) != MomentRule.cross else { return nil }
                    let wish = kinds[day % kinds.count]
                    let because = m.noticing.flatMap {
                        Notices.wishReason(today: m.company(), digests: $0.digests(), daysOld: core.dayCount(at: now), at: wall, time: time)
                    }
                    return IdleBeat.Candidate(.wish, signs: Asks.wishSign(m.steering.asks, wish, day: day).map { [$0] } ?? [], wish: wish, because: because)
                case .ask:
                    return m.askable(now, Asks.questions(m.steering.asks)).first.map { IdleBeat.Candidate(.ask, signs: [$0.question], ask: $0) }
                case .remembered:
                    return m.felt(now).first.map { IdleBeat.Candidate(.remembered, signs: [$0.line], remembered: $0) }
                case .musing:
                    let t = m.company()
                    return IdleBeat.Candidate(.musing, signs: Signs.musings(m.steering.signs, tags: tags, turns: t?.turns ?? 0, thread: t?.thread ?? ""))
                }
            }
            if forced { return IdleBeat.every(offer: offer) }
            return IdleBeat.due(room: room, quiet: talk() == .quiet, wishOpen: core.wish != nil, offer: offer).map { [$0] } ?? []
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
            if let effects = m.effects { effects(fx) } else { pipeline?.effects(fx, at: at) }
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
        }, speaks: m.speaks, pack: pack, signs: m.steering.signs,
        calendar: { core.calendar(at: $0.at) + m.answerTags($0.at) },
        replies: m.steering.replies, status: { [weak h] said in
            // What this buddy's agents are up to as you ask, and how
            // each one's latest check or turn came out.
            guard let h, let words = said["words"]?.string else { return nil }
            let now = h.clock.now(), log = h.log.view(now: now)
            return StatusReply.answer(core.status(at: now, results: view.results(log), asked: view.asked(log)), words: words, at: now,
                                      stretchSince: core.stretchSince(at: now))
        }, moment: { core.moment(at: $0.at) }, quiet: { at in
            // Asked to hush: quiet for a while.
            core.quiet(at: at)
        }, nap: { at in
            carryOut(core.nap(at: at), at)
        }, talk: talk, swears: m.swears, reason: { [weak h] about in
            // Why, from the line the brain read for it. Weak: the
            // harness holds this output.
            guard let h, let about else { return nil }
            let line = h.line(about.seq)
            let why = Narration.of(about, line: line, untouchedMs: ContextSection.untouchedMs(m.company(), at: h.clock.now()),
                                   name: pack.name)
            // Your goodnight says the day's turns, on the board too.
            if about.type == .lock, about.phase == .start, core.calendar(at: about.at).contains("night"),
               let turns = Notices.goodnight(turns: m.company()?.turns ?? 0), let why {
                return Narration(cause: why.cause + " " + turns, fact: String(turns.dropLast()))
            }
            let noted = why?.noting(noticedAt(about, line))
            // The day's first hello's caption keeps to the day and the dream.
            guard line?.facts[TranscriptView.firstTodayFact] != nil, let days = core.dayCount(at: about.at) else { return noted }
            return Narration.day(days, leading: noted)
        }, moodMoved: { [mood] now, log in
            MoodOutput.boardFact(mood, log, now: now, pack: pack)
        }, note: { fact, at in
            carryOut([.reaction(Moment(reason: fact))], at)
        }, dreams: m.steering.dreams, line: { [weak h] about in h?.line(about.seq) },
        asks: m.steering.asks, idleBeat: idleBeat, makeWish: { kind, at in
            carryOut(core.makeWish(kind, at: at), at)
        },
        moodFace: { [mood] log in MoodOutput.face(mood, log, pack: pack) },
        moodID: { [mood] log in MoodOutput.value(mood, log, pack: pack) },
        moodLevel: { [mood] log in MoodOutput.level(mood, log) },
        today: m.company, seed: m.seed)
        h.output(mood)
        react.earned = { e in e.flatMap { m.earned($0.seq) } }
        // The result card the finished turn's agent handed in: the lines
        // it offered play after the finish (`MomentRule.offeredLine`).
        react.offered = { [weak h] now in
            guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts) else { return nil }
            return core.result(for: key)
        }
        react.lineRoom = m.lineRoom
        h.output(react, openFor: MomentOutput.openForMs, keepOpen: TranscriptView.heldByPokes)
        // The Moments the rules make whole, with no pass: your bye at a
        // lock and your hello at an unlock, a working check-in, another
        // buddy's gesture. Each plays
        // as its event is logged, unless something holds the screen.
        for kind in TranscriptView.ruled + [TranscriptView.ruledCheckIn] {
            h.on(kind) { [weak h, weak react] e in
                guard let h, let react, TranscriptView.isRuled(e), let line = h.line(e.seq) else { return }
                let log = h.log.view(now: h.clock.now())
                guard view.held(e, log, needsYou: { core.needsYouBlock }) == nil,
                      let ruled = react.ruled(e, facts: line.facts, log: log) else { return }
                h.force(react, by: "rule") { react.play(ruled, about: e, log: log) }
            }
        }
        // The only buddy goes by the name you gave it, which the pack's
        // own words don't know.
        let own = CharacterPack.active.name
        let renamed = pack.name == own ? "" : "\n\(own) goes by \(pack.name) here: the name the person gave it."
        h.section { _, _ in m.steering.guide + renamed + "\n" + EventLine.reading(pack.name) + "\n" + EventLine.words(pack.name) }
        h.section { _, _ in m.steering.personality.text }
        // What it remembers, after who it is and before how it feels.
        h.section { _, _ in m.memory() }
        h.section { log, _ in
            m.steering.mood(MoodOutput.value(mood, log, pack: pack), in: pack) + (MoodOutput.levelLine(mood, log, pack: pack).map { "\n" + $0 } ?? "")
        }
        // How things stand: when it is, the talk setting, the buddy,
        // you, the agents, the day so far. Last before HISTORY.
        h.section { [weak h] log, _ in
            guard let h else { return nil }
            let now = h.clock.now()
            let newest = log.events.last { !$0.fromHarness }
            let wall = core.wall(now), time = core.config.time
            // With no growth store (a demo, an eval), a level 1 with an empty ring.
            let growth = core.growth() ?? Growth()
            let buddy = ContextSection.Buddy(level: growth.level, today: growth.today,
                                             daysOld: core.config.hatched.map { time.days(from: $0, to: wall) })
            let when = ContextSection.when(at: wall, specialDays: Days.words(at: wall, hatched: core.config.hatched, name: pack.name, time: time),
                                           time: time)
            return ContextSection.section(when: when, talk: talk(), quietForMs: core.quietUntil(at: now).map { $0 - now },
                                          buddy: buddy, company: m.company(),
                                          agents: core.status(at: now, results: [:]),
                                          wish: core.wishRow(name: pack.name),
                                          noticed: newest.flatMap { e in noticedAt(e, h.line(e.seq)) },
                                          at: now, name: pack.name)
        }
        h.closing { _, now, log, _ in MoodOutput.sinceLine(mood, log, at: now, name: m.buddy.name) }
        h.reachBack { _, now, log in view.workingSince(at: now, log) }
        return mood
    }
}
