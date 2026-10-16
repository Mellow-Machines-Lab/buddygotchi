import Foundation
import LinkKit
import MellowHarness

// The buddies: each board's link, core, mood and reactions, and how the
// brain answers for each. One buddy runs as Boop always has: nothing in
// the transcript names it.
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

    /// One buddy as it runs: its board's link, its own core, which hears
    /// only its own agents, its mood and its reactions on the board. On
    /// `home`.
    final class Rig: @unchecked Sendable {
        /// Nil for the only buddy, which nothing tags.
        let buddy: Buddy?
        let link: DeviceLink
        let transport: Transport?
        let core: Core
        let steering: Steering
        let reactions = Reactions()
        var mood: Choice!
        /// The newest snapshot sent to its board.
        var latest: StateSnapshot?
        /// The transport's `trouble` as the status last had it.
        var linkTrouble: String?

        init(buddy: Buddy?, link: DeviceLink, transport: Transport?, core: Core, steering: Steering) {
            self.buddy = buddy
            self.link = link
            self.transport = transport
            self.core = core
            self.steering = steering
        }

        var id: String? { buddy?.id }

        /// `body` with this buddy's pack in scope.
        func run<R>(_ body: () -> R) -> R { buddy?.pack.run(body) ?? body() }
    }

    /// What the buddy `id` is called: the first's, or the only one's, name
    /// from `long-term.md`.
    public func name(of id: String?) -> String { id.flatMap { id in buddies.first { $0.id == id }?.name } ?? name }

    /// Every buddy's board has said who it is: those with no link aside.
    public var helloFromEvery: Bool { rigs.allSatisfy { $0.transport == nil || $0.link.hello != nil } }

    /// The rig of the buddy `id`, the first's for none or one it doesn't run.
    func rig(_ id: String?) -> Rig { id.flatMap { id in rigs.first { $0.id == id } } ?? rigs[0] }

    /// The buddies as MellowHarness's voices hear them: with several, each
    /// event is answered by its own buddy first, then the others; a buddy's
    /// reaction by the others only.
    static func speakers(_ e: Event, _ buddies: [Buddy]) -> [String] {
        let ids = buddies.map(\.id)
        guard let own = Buddy.of(e), ids.contains(own) else { return ids }
        let others = ids.filter { $0 != own }
        return e.type == .reacted ? others : [own] + others
    }

    /// Registers one buddy's brain on `h`: its mood and react outputs and
    /// its prompt's sections, the guide with how to read the rest,
    /// PERSONALITY, what its `nature` adds, and MOOD. With several buddies
    /// (`voice` set) they're its voice's alone, and its prompt opens with
    /// whom it answers for (`Buddy.header`). Returns its mood.
    static func brain(on h: Harness, buddy: Buddy?, among all: [Buddy], steering: Steering, view: TranscriptView,
                      core: Core, personality: @escaping () -> Personality, reactions: Reactions,
                      queue: @escaping (DeviceReaction, Pending) -> Void, speaks: @escaping () -> Bool,
                      nature: LongTerm.Nature?) -> Choice {
        let voice = buddy?.id
        func scope<R>(_ body: () -> R) -> R { buddy?.pack.run(body) ?? body() }
        let mood = MoodOutput.choice(voice: voice, pack: buddy?.pack)
        // A reaction your tap cut short is in progress while the pokes go
        // on, and done once anything else happens.
        // A reaction's end, MellowHarness's own event, never stops the pokes.
        // The rule holds the log, not the harness, which holds the rule.
        let transcript = h.log
        h.on("*") { e in
            guard !reactions.cutByTap.isEmpty, TranscriptView.stopsThePokes(e, transcript.view(before: e)) else { return }
            reactions.pokesStopped()
        }
        let react = scope {
            ReactOutput(queue: queue, blocked: { core.reactionBlock }, who: { [weak h] now in
                // Weak: the harness holds this output.
                guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts),
                      let who = view.who(about: key, h.log.view(now: h.clock.now())) else { return nil }
                return DeviceReaction.Who(agent: who.agent, thread: who.thread, opens: who.opens)
            }, speaks: speaks, seed: buddy.map { $0.id.utf8.reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) } } ?? 0)
        }
        let mine = { (asked: Harness.Voice?) in asked?.id == voice }
        h.output(mood, voice: voice)
        h.output(buddy == nil ? react : Scoped(react, buddy), voice: voice, openFor: ReactOutput.openForMs,
                 keepOpen: TranscriptView.heldByPokes)
        if let buddy { h.section { _, v in mine(v) ? Buddy.header(for: buddy, among: all) : nil } }
        h.section { _, v in mine(v) ? scope { steering.guide + "\n" + EventLine.reading + "\n" + EventLine.words } : nil }
        h.section { _, v in mine(v) ? steering.personality(personality()).text : nil }
        h.section { _, v in mine(v) ? nature.flatMap(steering.nature) : nil }
        h.section { log, v in mine(v) ? scope { steering.mood(MoodOutput.value(mood, log)) } : nil }

        return mood
    }

    /// An output run with its buddy's pack in scope, so its questions and
    /// what it did name that buddy.
    final class Scoped: Output {
        let inner: any Output
        let buddy: Buddy?
        init(_ inner: any Output, _ buddy: Buddy?) {
            self.inner = inner
            self.buddy = buddy
        }

        var name: String { inner.name }
        func questions(now: Event?, log: LogView) -> [Question] {
            buddy?.pack.run { inner.questions(now: now, log: log) } ?? inner.questions(now: now, log: log)
        }
        func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
            buddy?.pack.run { inner.run(answers, now: now, log: log) } ?? inner.run(answers, now: now, log: log)
        }
    }
}
