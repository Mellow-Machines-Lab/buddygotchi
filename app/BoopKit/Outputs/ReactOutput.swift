import Foundation
import MellowHarness

/// Whether Boop reacts to NOW: with which mood's face, which animation,
/// for how long, and what it says. A reaction
/// is a mood × a visual for a while: the device draws that mood's design
/// of whatever look is showing, or of the animation picked (a turn's
/// finish: task_complete for its outcome, or reply_ready), for a number of
/// its loops. Jev picks what Boop says as a feeling, a
/// topic and a kind, and Voice finds a recorded take of each in the face's
/// mood and joins them into a `say`, or finds none, and then the face plays
/// in silence. It waits in the device's queue until whatever plays there
/// has finished. It's started, not done,
/// until whoever plays it ends its handle.
public final class ReactOutput: Output {
    public static let outputName = "react"
    public let name = ReactOutput.outputName
    /// Sends a brain reaction, which waits in the device's queue behind
    /// whatever is playing, with the handle to end once the device says how
    /// it ended, or once it never will.
    let queue: (DeviceReaction, Pending) -> Void
    /// Why a reaction can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// The agent and thread the event the brain answers is about, or nil
    /// (a poke, an idle heartbeat): a finish names it on the device.
    let who: (Event?) -> DeviceReaction.Who?
    /// Whether the device plays the takes Voice picks from: false while its
    /// card has another pack, or none, and then Boop says
    /// nothing.
    let speaks: () -> Bool
    /// Picks among the takes that fit, and remembers the last `say`'s
    /// words, which aren't said again while another fits.
    var takes = SplitMix64(seed: 0x7A4E)
    var lastWords: Set<String> = []
    /// Picks each finish's variation, never the last one of its animation.
    var variants = SplitMix64(seed: 0xB00B)
    var lastVariant: [String: Int] = [:]
    public init(queue: @escaping (DeviceReaction, Pending) -> Void, blocked: @escaping () -> String?,
                who: @escaping (Event?) -> DeviceReaction.Who? = { _ in nil }, speaks: @escaping () -> Bool = { true }) {
        self.queue = queue
        self.blocked = blocked
        self.who = who
        self.speaks = speaks
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// Each expression: a mood's name, in `MoodOutput.moods`' order, and
    /// what the face means for this reaction, from the
    /// pack's moods' `face`, else their meaning (characters/CHARACTER.md
    /// §5). It's the
    /// reaction's face only, never the lasting mood. What it says is a take
    /// performed in that mood (`Voice`).
    public static var expressions: [Option] { CharacterPack.active.faces }

    /// How Boop can feel about NOW, in the order `say.feeling` offers them.
    /// Every feeling take has one, and every face has
    /// takes of each: tests check both, so all are offered.
    public static let feelings = [
        Option("upset", "Something went wrong or let \(CharacterPack.active.name) down: a check or a turn failing, the agent stuck or giving up, rude words or sad news.",
               notFor: "A win, a poke, or work going on, however long."),
        Option("glad", "Something went right: a turn done and working, a check passing, a big win, thanks or kind words.",
               notFor: "A failure, or work still going on."),
        Option("tickled", "Poked or teased: a poke, a tap, or playful words to \(CharacterPack.active.name).",
               notFor: "A failure, or the agent's work."),
    ]

    /// What NOW can be about, in the order `say.about` offers them:
    /// each a topic NOW's line shows. Every topic take
    /// has one, and every face has takes of each, as for `feelings`.
    public static let topics = [
        Option("start", "A turn starting: off it goes.", notFor: "Work going on, or a turn that finished."),
        Option("helpers", "The agent starting a subagent: helpers sent off."),
        Option("helper back", "A subagent finishing: a helper back with its report."),
        Option("retry", "The same thing again: a retry, a check run again after failing, or the person saying it's still broken.",
               notFor: "A first failure."),
        Option("work", "Work going on: edits, steady progress, a long or hard turn.", notFor: "A turn that finished."),
        Option("tests", "Tests: running, failing or passing."),
        Option("command", "A command or a build running in the terminal.", notFor: "Tests: they're tests."),
        Option("tool", "A tool: the web, an MCP tool, something fetched or looked up."),
        Option("looking", "Searching or reading: the agent looking through files, or something puzzling."),
        Option("planning", "Planning: the agent in plan mode, or thinking before it acts."),
        Option("done", "A turn finished, done and working.", notFor: "Anything but a success."),
        Option("answer", "A turn that only answered something or asked something back.", notFor: "Work done, or a failure."),
        Option("stopped", "A turn stopped: interrupted, or the agent giving up.", notFor: "A turn that finished done."),
        Option("waiting", "Waiting: a long command, or the agent waiting on something slow.",
               notFor: "Something that needs the person: the ding says that."),
        Option("quiet", "Nothing going on: a quiet check-in, or words to \(CharacterPack.active.name) about nothing in particular."),
        Option("hello", "The person back at the Mac after a break: a hello.",
               notFor: "Anything else: a poke, words to \(CharacterPack.active.name), a turn starting."),
    ]

    /// How big what it says is, plainest first:
    /// with none of the kind asked for, Voice takes the nearest one, but
    /// never a swear unless one was asked for.
    public static let kinds = [
        Option("sound", "A noise with no word: a huff, a grunt, a gasp. The usual."),
        Option("word", "One word that names the moment.", notFor: "A routine check-in."),
        Option("phrase", "A little catchphrase, for a moment worth remembering, now and then.",
               notFor: "Routine work, or a small win or failure."),
        Option("swear", "A swear, at a failure that really stings.",
               notFor: "A win, a poke, words to \(CharacterPack.active.name), or anything about the person."),
    ]

    /// The animations a reaction can play in its face: a
    /// turn's finish, judged from what NOW says. No rule plays a finish,
    /// so the brain judges each one's outcome.
    public static let animations = [
        Option("success", "NOW's line says a turn finished, done, and its last message, if any, says the work is done and working.",
               notFor: "A check that passed while the turn goes on, a turn that finished failed, a message saying it couldn't finish or something is broken, or only an answer or a question back."),
        Option("failure", "NOW's line says a turn finished, failed; or finished done, but its last message says the agent couldn't finish or something is broken.",
               notFor: "A check that failed while the turn goes on, or a turn done whose message says the work is working."),
        Option("reply", "NOW's line says a turn finished, done, and its last message only answers something or asks something back, often with no tool calls: no task finished.",
               notFor: "Work done, a turn that finished failed, or anything but a turn that finished."),
    ]

    /// The animation `react.animation` picked, or nil for none, a missing
    /// answer or one the device doesn't play.
    public static func animation(_ answers: Answers) -> String? {
        let pick = answers["react.animation"]?.choice
        return animations.contains { $0.name == pick } ? pick : nil
    }

    /// What the device plays for an animation pick: the
    /// face's task_complete scene for a success or a failure, with that
    /// outcome, and its reply_ready for a reply.
    public static func finish(_ pick: String) -> (anim: String, outcome: String?) {
        switch pick {
        case "success", "failure": ("task_complete", pick)
        default: ("reply_ready", nil)
        }
    }

    /// How long the face holds, in loops of the design it's drawn in: the
    /// first holds once, and each one after a loop more.
    /// The longest hold of the longest design must end on the device
    /// before the link stops waiting for its `ended` (its `ttl` plus 60 s,
    /// linkkit/SPEC.md §5), or a reaction that played would read as
    /// failed: `testAReactionEndsBeforeTheHarnessCeiling` holds it so.
    public static let holds = [
        Option("once", "A small moment: the usual."),
        Option("twice", "A moment that stands out.", notFor: "Routine work."),
        Option("three times", "A big moment, such as a check passing after failing."),
        Option("four times", "The biggest moments: a hard-won finish, or a failure that keeps coming back.",
               notFor: "A single win or failure."),
    ]

    /// How many loops the face holds: `react.loops`' pick, or once when
    /// it's missing.
    public static func loops(_ answers: Answers) -> Int {
        (holds.firstIndex { $0.name == answers["react.loops"]?.choice } ?? 0) + 1
    }

    /// A reaction still in progress this long after it started is ended as
    /// failed: past the longest reaction, held
    /// four times in the design with the longest loop.
    public static let openForMs: Int64 = 90_000

    /// Below this, Jev is guessing, and silence beats a guessed meaning.
    public static let sayFloor = 0.35

    /// A `say` question's pick: its answer if it isn't
    /// `none`, reaches the floor and is one of `options`, else nil.
    static func pick(_ answers: Answers, _ key: String, _ options: [Option]) -> String? {
        guard let a = answers[key], a.choice != "none", a.p >= sayFloor,
              options.contains(where: { $0.name == a.choice }) else { return nil }
        return a.choice
    }

    /// How Boop feels, `say.feeling`'s pick, or nil.
    public static func feeling(_ answers: Answers) -> String? { pick(answers, "say.feeling", feelings) }
    /// What NOW is about, `say.about`'s pick, or nil.
    public static func about(_ answers: Answers) -> String? { pick(answers, "say.about", topics) }

    /// How big the feeling's take is: `say.kind`'s pick, or a sound when
    /// it's missing.
    public static func kind(_ answers: Answers) -> Take.Kind {
        answers["say.kind"].flatMap { Take.Kind(rawValue: $0.choice) } ?? .sound
    }

    public func questions(now: Event?, log: LogView) -> [Question] { Self.asked }

    /// The questions asked: a character pack with no voice is never asked
    /// what to say (characters/CHARACTER.md §8), so it has no `say.*` ones.
    static let asked: [Question] = Take.all.isEmpty ? questions.filter { !$0.key.hasPrefix("say.") } : questions

    /// Every question, built once: none of them changes.
    static let questions: [Question] = {
        let byBoth = "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"
        return [
            Question(key: "react.mood", text: "How should \(CharacterPack.active.name) react to NOW, if at all? It makes this mood's face for a moment, and may say something.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face, "
                                          + "or HISTORY shows \(CharacterPack.active.name) still making the one it calls for (in progress).",
                                      notFor: "Anything PERSONALITY's Examples react to that \(CharacterPack.active.name) isn't already doing.")]
                         + ReactOutput.expressions),
            Question(key: "react.animation", text: "If \(CharacterPack.active.name) reacts and NOW's line is a turn that finished, how did the turn end?",
                     about: "the NOW section", judgeBy: "NOW's line and the agent's last message under it",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed. A turn starting, a check passing or failing (tests, a build, a deploy), a poke, a check-in, words to \(CharacterPack.active.name) and a stopped turn all get none.")]
                         + ReactOutput.animations),
            Question(key: "react.loops", text: "If \(CharacterPack.active.name) reacts, how long does it hold the face?", about: "the NOW section",
                     judgeBy: byBoth, options: ReactOutput.holds),
            Question(key: "say.feeling", text: "If \(CharacterPack.active.name) reacts, how does it feel about NOW? It says so first, in its face's mood.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "No feeling to say: nothing in NOW is worth a sound.")] + ReactOutput.feelings),
            Question(key: "say.about", text: "If \(CharacterPack.active.name) reacts, what is NOW about? It names it after the feeling, in its face's mood.",
                     about: "the NOW section", judgeBy: "NOW's line",
                     options: [Option("none", "No topic to name: NOW's line isn't about any of these.")] + ReactOutput.topics),
            Question(key: "say.kind", text: "If \(CharacterPack.active.name) says something, how big is it?", about: "the NOW section",
                     judgeBy: byBoth, options: ReactOutput.kinds),
        ]
    }()

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        // 1. Does Jev want a reaction at all, and with which face?
        guard let choice = answers["react.mood"]?.choice, Self.expressions.contains(where: { $0.name == choice }) else {
            return nil
        }
        // 2. This output's own rules.
        if let why = blocked() { return .failed(why) }
        // 3. The effect: the face, and the `say`, if Voice has takes
        // for the feeling and the topic in this face's mood and the turn's
        // finish.
        let loops = Self.loops(answers)
        let pick = Self.animation(answers)
        let said = !speaks() ? [] : Voice.say(feeling: Self.feeling(answers), about: Self.about(answers), kind: Self.kind(answers),
                                               face: choice, finish: pick, avoiding: lastWords, rng: &takes)
        if !said.isEmpty { lastWords = Set(said.map(\.text)) }
        let say = DeviceReaction.Say(takes: said)
        var reaction = DeviceReaction(say: say, mood: choice, loops: loops)
        if let pick {
            // A finish: its scene, a variation of it for its outcome in the
            // face's design (never the last one), and whose turn it was.
            let (anim, outcome) = Self.finish(pick)
            let variant = Core.pickVariant(mood: choice, state: anim, outcome: outcome, avoiding: lastVariant[anim], &variants)
            lastVariant[anim] = variant
            reaction.anim = anim
            reaction.outcome = outcome
            reaction.variant = variant
            reaction.who = who(now)
        }
        let pending = Pending()
        queue(reaction, pending)
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the reaction ended.
        let did = pick.map { "\(CharacterPack.active.name) played \(Self.article($0)) \($0) in \(Self.article(choice)) \(choice) face" }
            ?? "\(CharacterPack.active.name) made \(Self.article(choice)) \(choice) face"
        // The takes' ids in order, for the tools to say what it said.
        return .started(did + ", held \(Self.holds[loops - 1].name)" + (say.text.map { ", and said \"\($0)\"." } ?? "."), pending,
                        facts: ["takes": .array(said.map { .string($0.id) })])
    }
}
