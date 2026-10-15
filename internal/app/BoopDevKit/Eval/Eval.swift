import BoopKit
import Foundation
import MellowHarness
import LinkKit

/// The harness evals (internal/EVALS.md): scenarios of hook-level steps on a
/// virtual clock, run through a fresh core, the real harness and the real
/// actions, each pass checked against what Jev should answer. They ask Jev,
/// so they need its key; `boopdev eval` fails without it. Tests run the same
/// runner with a scripted brain.
public struct Scenario: Sendable {
    /// One step: what happens, and what the pass it wakes should lead to.
    public struct Step: Sendable {
        /// `turn started`, `command`, `turn finished`, `turn failed`,
        /// `poke`, `pokes`, `said` or `wait`.
        public var event: String
        /// Virtual time since the scenario started, in ms.
        public var atMs: Int64
        /// The thread's workspace; it's always Claude's, in `landing`.
        public var workspace: String?
        /// Claude's session, `s1` unless the step says: another session is
        /// another thread, working at the same time.
        public var session: String?
        /// A command: its topic, and whether it failed.
        public var topic: String?
        public var failed: Bool?
        /// A failed turn's error class.
        public var error: String?
        /// What you asked, on a turn start, and the agent's last message,
        /// on a finish: the two notes Jev reads.
        public var prompt: String?
        public var message: String?
        /// What you said to Boop, for `said`.
        public var words: String?
        /// How a reaction this step's passes start ends: `done` (the
        /// default), `in progress` (it never ends), or `failed: <why>`.
        public var reaction: String?
        /// What the pass should come to; nil checks nothing. A step with an
        /// expectation must wake the brain.
        public var expect: Expectation?
    }

    /// What a pass should come to: each a set of acceptable values, `none`
    /// included where staying quiet or saying nothing is fine.
    public struct Expectation: Sendable, Equatable {
        /// Jev's `react.mood` pick: `none` or a mood's face.
        public var react: Set<String>?
        /// The animation the reaction played (`react.animation`'s pick), or
        /// `none` when it played none or Boop didn't react.
        public var animation: Set<String>?
        /// How Boop felt (`say.feeling`'s pick, when it reached the floor),
        /// or `none`.
        public var feeling: Set<String>?
        /// What NOW was about (`say.about`'s pick, when it reached the
        /// floor), or `none`.
        public var about: Set<String>?
        /// How it asked to say it (`say.kind`'s pick), or `none` when Boop
        /// didn't react.
        public var kind: Set<String>?
        /// A take Boop said, by its text as the bubble shows it (`Tsk...`):
        /// the step passes when any of the line's takes is one of these;
        /// with `some`, when it said anything; with `none`, when it said
        /// nothing.
        public var said: Set<String>?
        /// How long the face held (`react.loops`' pick), or `none` when
        /// Boop didn't react.
        public var loops: Set<String>?
        /// The mood after the pass.
        public var mood: Set<String>?
        /// Exactly the options the pass's mood question offered: staying
        /// in the mood it had, and its moves on the graph.
        public var offered: Set<String>?

        public init(react: Set<String>? = nil, animation: Set<String>? = nil, feeling: Set<String>? = nil, about: Set<String>? = nil,
                    kind: Set<String>? = nil, said: Set<String>? = nil, loops: Set<String>? = nil,
                    mood: Set<String>? = nil, offered: Set<String>? = nil) {
            self.react = react
            self.animation = animation
            self.feeling = feeling
            self.about = about
            self.kind = kind
            self.said = said
            self.loops = loops
            self.mood = mood
            self.offered = offered
        }
    }

    /// Checks over a whole run rather than one pass (internal/EVALS.md §3):
    /// how lively Boop stays. Each is loose on purpose, there to catch a
    /// clear failure.
    public struct Checks: Sendable, Equatable {
        /// `max_quiet_working`: the longest a turn may run with no reaction
        /// played, counted from the turn's start or the last reaction.
        public var quietWorkingMs: Int64?
        /// `max_same_in_a_row`: how many reactions in a row may be the same
        /// face, animation and what it said.
        public var sameInARow: Int?
        /// `mood_changes`: how many times the mood may change in the run.
        public var moodChanges: ClosedRange<Int>?
        /// `no_mood_bounce_within`: a mood may not change back to the one it
        /// just left sooner than this.
        public var bounceMs: Int64?
        /// `reactions`: how many reactions the run may play.
        public var reactions: ClosedRange<Int>?
        /// `min_variety`: the fewest different reactions (face, animation
        /// and what it said) the run must play.
        public var variety: Int?
        /// `moves_on_graph`: every pass's mood answer was one of the
        /// options it offered, and every mood change was a move on the
        /// mood graph.
        public var onGraph = false

        public init() {}
        static let keys = ["max_quiet_working", "max_same_in_a_row", "mood_changes", "no_mood_bounce_within",
                           "reactions", "min_variety", "moves_on_graph"]
    }

    public var name: String
    /// The situation and what Boop should do in it, in plain words and
    /// with no harness terms, so the steps can be rewritten to fit it when
    /// the harness changes (the file's `case`).
    public var story: String
    public var why: String
    /// Boop's character, not a tuning target: runs 3 times by default, and
    /// `boopdev eval --always` runs only these.
    public var always: Bool
    /// How many runs it gets when `--runs` doesn't say, if not the default
    /// for its kind (`Eval.runs`).
    public var runs: Int?
    public var checks: Checks?
    /// A known gap: why Boop can't pass this today, and what would fix it.
    /// Its failures are reported but don't fail the eval, and the report
    /// says when it passes after all.
    public var gap: String?
    public var personality: Personality
    /// The mood the run starts in, as the dashboard would set it just
    /// before: calm, the resting mood, unless the file says.
    public var mood: String
    public var graph: MoodGraph.Version
    public var steps: [Step]
    public var file: String

    public static let events = ["turn started", "command", "turn finished", "turn failed", "poke", "pokes", "said",
                                "away", "back", "wait"]

    /// How a reaction ends, from a step's `reaction`: nil for a value it
    /// doesn't take.
    static func end(_ text: String) -> Pending.End?? {
        if text == "done" { return .some(.done) }
        if text == "in progress" { return .some(nil) }
        if text.hasPrefix("failed: "), text.count > 8 { return .some(.failed(String(text.dropFirst(8)))) }
        return nil
    }

    /// Reads one scenario file. Throws with the file and step on a bad one.
    public init(file: URL) throws {
        self.file = file.lastPathComponent
        func bad(_ why: String) -> Error { EvalError("\(file.lastPathComponent): \(why)") }
        guard let o = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else { throw bad("not a JSON object") }
        guard let name = o["name"] as? String, let story = o["case"] as? String, let why = o["why"] as? String,
              let raw = o["steps"] as? [[String: Any]]
        else { throw bad("needs name, case, why and steps") }
        let unknownKeys = Set(o.keys).subtracting(["name", "case", "why", "always", "runs", "gap", "personality", "mood", "graph", "checks", "steps"])
        guard unknownKeys.isEmpty else { throw bad("unknown key \(unknownKeys.sorted().joined(separator: ", "))") }
        self.name = name
        self.story = story
        self.why = why
        always = o["always"] as? Bool ?? false
        gap = o["gap"] as? String
        if always, gap != nil { throw bad("an always scenario can't be a known gap") }
        if let r = o["runs"] {
            guard let n = r as? Int, n >= 1 else { throw bad("runs is a count, 1 or more") }
            runs = n
        }
        if let c = o["checks"] {
            guard let c = c as? [String: Any] else { throw bad("checks is an object") }
            let unknown = Set(c.keys).subtracting(Checks.keys)
            guard unknown.isEmpty else { throw bad("checks has only \(Checks.keys.joined(separator: ", "))") }
            func time(_ key: String) throws -> Int64? {
                guard let v = c[key] else { return nil }
                guard let t = v as? String, let ms = Scenario.ms(t) else { throw bad("checks.\(key) is like 5m or 90s") }
                return ms
            }
            func count(_ key: String) throws -> Int? {
                guard let v = c[key] else { return nil }
                guard let n = v as? Int, n >= 0 else { throw bad("checks.\(key) is a count") }
                return n
            }
            func range(_ key: String) throws -> ClosedRange<Int>? {
                guard let v = c[key] else { return nil }
                guard let t = v as? String, let r = Scenario.range(t) else { throw bad("checks.\(key) is like 1-3, 2- or -4") }
                return r
            }
            var checks = Checks()
            checks.quietWorkingMs = try time("max_quiet_working")
            checks.sameInARow = try count("max_same_in_a_row")
            checks.moodChanges = try range("mood_changes")
            checks.bounceMs = try time("no_mood_bounce_within")
            checks.reactions = try range("reactions")
            checks.variety = try count("min_variety")
            if let v = c["moves_on_graph"] {
                guard let on = v as? Bool, on else { throw bad("checks.moves_on_graph is true") }
                checks.onGraph = true
            }
            self.checks = checks
        }
        personality = try (o["personality"] as? String).map {
            guard let p = Personality(rawValue: $0) else { throw bad("unknown personality \($0)") }
            return p
        } ?? .default
        guard let graph = MoodGraph.Version(rawValue: o["graph"] as? String ?? "v2") else { throw bad("graph is v2 or v3") }
        self.graph = graph
        let graphMoods = MoodGraph.moods(for: graph)
        mood = try (o["mood"] as? String).map {
            guard graphMoods.contains($0) else { throw bad("mood is one of \(graphMoods.joined(separator: ", "))") }
            return $0
        } ?? MoodAction.initial
        steps = try raw.enumerated().map { i, s in
            func badStep(_ why: String) -> Error { bad("step \(i + 1): \(why)") }
            guard let event = s["event"] as? String, Scenario.events.contains(event) else {
                throw badStep("event is one of \(Scenario.events.joined(separator: ", "))")
            }
            guard let at = s["at"] as? String, let atMs = Scenario.ms(at) else { throw badStep("at is like 0m, 90s or 2m30s") }
            var step = Step(event: event, atMs: atMs)
            step.workspace = s["workspace"] as? String
            step.session = s["session"] as? String
            step.topic = s["topic"] as? String
            step.failed = s["failed"] as? Bool
            step.error = s["error"] as? String
            step.prompt = s["prompt"] as? String
            step.message = s["message"] as? String
            if step.prompt != nil, event != "turn started" { throw badStep("prompt is only for turn started") }
            if step.message != nil, event != "turn finished" { throw badStep("message is only for turn finished") }
            step.words = s["words"] as? String
            if event == "said", step.words?.isEmpty != false { throw badStep("said needs words") }
            if let reaction = s["reaction"] {
                guard let text = reaction as? String, Scenario.end(text) != nil else {
                    throw badStep("reaction is done, in progress or failed: <why>")
                }
                step.reaction = text
            }
            if let e = s["expect"] as? [String: Any] {
                func set(_ key: String) throws -> Set<String>? {
                    guard let v = e[key] else { return nil }
                    guard let text = v as? String else { throw badStep("expect.\(key) is like \"proud|excited\"") }
                    return Set(text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                }
                let keys = ["react", "animation", "feeling", "about", "kind", "said", "loops", "mood", "offered"]
                let unknown = Set(e.keys).subtracting(keys)
                guard unknown.isEmpty else { throw badStep("expect has only \(keys.joined(separator: ", "))") }
                step.expect = Expectation(react: try set("react"), animation: try set("animation"), feeling: try set("feeling"), about: try set("about"),
                                          kind: try set("kind"), said: try set("said"), loops: try set("loops"),
                                          mood: try set("mood"), offered: try set("offered"))
                for (key, values, known) in [("feeling", step.expect?.feeling, ReactAction.feelings.map(\.name)),
                                             ("about", step.expect?.about, ReactAction.topics.map(\.name)),
                                             ("kind", step.expect?.kind, ReactAction.kinds.map(\.name))] {
                    let unknown = (values ?? []).subtracting(known + ["none"])
                    guard unknown.isEmpty else { throw badStep("expect.\(key) has \(unknown.sorted().joined(separator: ", ")), not one of \(known.joined(separator: ", "))") }
                }
                let texts = Set(Take.all.map(\.text))
                let unsaid = (step.expect?.said ?? []).subtracting(texts.union(["none", "some"]))
                guard unsaid.isEmpty else { throw badStep("expect.said has \(unsaid.sorted().joined(separator: ", ")), not a take's text") }
                for (key, values) in [("react", step.expect?.react), ("mood", step.expect?.mood), ("offered", step.expect?.offered)] {
                    let unknown = (values ?? []).subtracting(graphMoods + (key == "react" ? ["none"] : []))
                    guard unknown.isEmpty else { throw badStep("expect.\(key) has \(unknown.sorted().joined(separator: ", ")), not a mood") }
                }
                let finishes = ["none"] + ReactAction.animations.map(\.name)
                guard (step.expect?.animation ?? []).isSubset(of: finishes) else {
                    throw badStep("expect.animation is one of \(finishes.joined(separator: ", "))")
                }
            }
            return step
        }
        guard checks != nil || steps.contains(where: { $0.expect != nil }) else { throw bad("expects nothing") }
    }

    /// `1-3`, `2-` (2 or more), `-4` (4 at most) or `3`.
    static func range(_ text: String) -> ClosedRange<Int>? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 { return Int(parts[0]).map { $0...$0 } }
        guard parts.count == 2, !(parts[0].isEmpty && parts[1].isEmpty) else { return nil }
        guard let low = parts[0].isEmpty ? 0 : Int(parts[0]), let high = parts[1].isEmpty ? Int.max : Int(parts[1]),
              low <= high else { return nil }
        return low...high
    }

    /// `2m30s`, `90s`, `5m`, `1h`.
    static func ms(_ text: String) -> Int64? {
        var total: Int64 = 0
        var number = ""
        for c in text {
            if c.isNumber { number.append(c); continue }
            guard let n = Int64(number) else { return nil }
            switch c {
            case "h": total += n * 3_600_000
            case "m": total += n * 60_000
            case "s": total += n * 1000
            default: return nil
            }
            number = ""
        }
        return number.isEmpty ? total : nil
    }

    public static func load(directory: URL) throws -> [Scenario] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(Scenario.init(file:))
    }
}

public struct EvalError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Runs scenarios (internal/EVALS.md §2).
public struct Eval {
    /// What one checked step came to.
    public struct Check: Sendable {
        public var step: Int
        public var line: String
        public var expected: Scenario.Expectation
        /// What happened: the react.mood pick, the animation played, the
        /// feeling, topic and kind picked, the line said and its takes, how
        /// long the face held, the mood after.
        public var react: String?
        public var animation: String?
        public var feeling: String?
        public var about: String?
        public var kind: String?
        public var said: String?
        public var saidTakes: [String] = []
        public var loops: String?
        public var mood: String
        /// What the pass's mood question offered.
        public var offered: [String] = []
        public var dropped: String?
        public var latencyMs: Int

        public var passed: Bool {
            guard dropped == nil else { return false }
            if let r = expected.react, !r.contains(react ?? "none") { return false }
            if let a = expected.animation, !a.contains(animation ?? "none") { return false }
            if let f = expected.feeling, !f.contains(feeling ?? "none") { return false }
            if let a = expected.about, !a.contains(about ?? "none") { return false }
            if let k = expected.kind, !k.contains(kind ?? "none") { return false }
            if let s = expected.said, !(saidTakes.isEmpty ? s.contains("none") : s.contains("some") || saidTakes.contains(where: s.contains)) {
                return false
            }
            if let l = expected.loops, !l.contains(loops ?? "none") { return false }
            if let m = expected.mood, !m.contains(mood) { return false }
            if let o = expected.offered, o != Set(offered) { return false }
            return true
        }

        public var summary: String {
            let want = [expected.react.map { "react \($0.sorted().joined(separator: "|"))" },
                        expected.animation.map { "animation \($0.sorted().joined(separator: "|"))" },
                        expected.feeling.map { "feeling \($0.sorted().joined(separator: "|"))" },
                        expected.about.map { "about \($0.sorted().joined(separator: "|"))" },
                        expected.kind.map { "kind \($0.sorted().joined(separator: "|"))" },
                        expected.said.map { "said \($0.sorted().joined(separator: "|"))" },
                        expected.loops.map { "loops \($0.sorted().joined(separator: "|"))" },
                        expected.mood.map { "mood \($0.sorted().joined(separator: "|"))" },
                        expected.offered.map { "offered \($0.sorted().joined(separator: "|"))" }].compactMap { $0 }
            let got = dropped.map { "dropped: \($0)" }
                ?? "react \(react ?? "none"), animation \(animation ?? "none"), feeling \(feeling ?? "none"), about \(about ?? "none"), kind \(kind ?? "none"), said \(said ?? "none"), loops \(loops ?? "none"), mood \(mood)"
                + (expected.offered == nil ? "" : ", offered \(offered.sorted().joined(separator: "|"))")
            return "  step \(step): \(line)\n    wanted \(want.joined(separator: ", ")); got \(got)"
        }
    }

    /// A reaction as the person sees it; two are the same when all of it
    /// is, however long each held.
    public struct Reaction: Sendable, Hashable {
        public var face: String
        public var animation: String
        /// The take's text, or `none`.
        public var said: String
        public var text: String {
            face + (animation == "none" ? "" : " \(animation)") + (said == "none" ? "" : " \"\(said)\"")
        }
    }

    /// One pass of a run, checked or not, for the whole-run checks and the
    /// timeline.
    public struct Pass: Sendable {
        /// Virtual ms since the run started.
        public var atMs: Int64
        public var line: String
        /// What played, if Boop reacted, and how long the face held.
        public var reaction: Reaction?
        public var loops: String?
        /// The mood after the pass.
        public var mood: String
        public var dropped: String?
        /// What the mood question offered, and Jev's answer to it.
        public var offered: [String] = []
        public var answer: String?
    }

    /// A whole-run check's outcome.
    public struct RunCheck: Sendable {
        public var name: String
        public var passed: Bool
        /// What was allowed and what came.
        public var detail: String
        public var summary: String { "  whole run: \(name): \(detail)" }
    }

    public struct Result: Sendable {
        public var scenario: String
        public var file: String
        public var checks: [Check]
        public var runChecks: [RunCheck] = []
        public var timeline: [Pass] = []
        public var passed: Bool { checks.allSatisfy(\.passed) && runChecks.allSatisfy(\.passed) }
    }

    let brain: any Brain
    let steering: Steering

    /// Every entry of every run, one JSON line each, as debug mode writes them.
    public var debugLog: URL?

    public init(brain: any Brain, steering: Steering) {
        self.brain = brain
        self.steering = steering
    }

    /// How many runs a scenario gets unless `--runs` says (internal/EVALS.md
    /// §2): its own `runs`, else 3 for an `always` one, Boop's character,
    /// and 1 for the rest.
    public static func runs(_ scenario: Scenario) -> Int { scenario.runs ?? (scenario.always ? 3 : 1) }

    /// About how many requests one run of a scenario sends Jev: its passes
    /// with the scripted brain, no key needed. A real run can differ by a
    /// pass or two, since what Jev answers can move what wakes it later.
    public static func requests(_ scenario: Scenario, steering: Steering) async throws -> Int {
        try await Eval(brain: ScriptedBrain.pipelineCheck, steering: steering).run(scenario).timeline.count
    }

    /// One run of a scenario, from a fresh core and transcript, the mood
    /// in it.
    public func run(_ scenario: Scenario) async throws -> Result {
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let start = Replay.defaultStart
        let clock = VirtualClock(start)
        let rules = steering.personality(scenario.personality).rules
        let core = Core(config: .init(time: time, seed: 1), lastActiveDay: time.day(start))
        core.setWallClock(start, at: start)
        let view = TranscriptView(rules: rules, seed: 1)
        let home = DispatchQueue(label: "boop.eval")
        // The brain is asked for each event straight through, not by the
        // loop (`respond`), on the virtual clock.
        let pipeline = Pipeline(core: core, view: view, time: time, clock: Harness.Clock(now: { clock.now }), queue: home,
                                loop: false)
        // A fake device: a reaction goes nowhere and ends as the step says,
        // played at once by default, its `ended` read as the app reads the
        // device's (`Reactions`), so HISTORY reads as the app's does once it
        // has; one left in progress stays so.
        let ending = Ending()
        let reactions = Reactions()
        let (harness, mood) = Runtime.harness(
            pipeline: pipeline, steering: steering, personality: { scenario.personality }, reactions: reactions,
            queue: { moment, pending in
                ending.said = moment.say?.text
                ending.takes = moment.say?.takes.map(\.text) ?? []
                guard let end = ending.end else { return ending.open.append(pending) }
                if let ended = Eval.ended(end) {
                    reactions.read(.ended(ended), pending).map(pending.finish)
                } else {
                    pending.finish(end)
                }
            }, version: scenario.graph, face: { scenario.graph == .v3 ? .gel : .pixel })
        if let url = debugLog {
            let writer = Runtime.debugLines(pipeline: pipeline, emit: { LineFile.append($0, to: url) })
            harness.onPass = { pass in writer.pass(pass, launchOptions: [:], at: clock.now) }
        }
        func moodNow() -> String { home.sync { MoodAction.value(mood, harness.log.view(now: clock.now), version: scenario.graph) } }
        home.sync {
            harness.use(brain)
            // The mood it starts in, as the dashboard would set it just before.
            if scenario.mood != MoodAction.initial {
                harness.force(mood, by: Runtime.forcedBy) {
                    MoodAction.change(mood, to: scenario.mood, log: harness.log.view(now: clock.now), version: scenario.graph)
                }
            }
        }

        var checks: [Check] = []
        var timeline: [Pass] = []
        // When any of the scenario's turns works, from the steps: [start, end].
        var working: [(Int64, Int64)] = []
        var since: Int64?
        var open: Set<String> = []
        for (i, step) in scenario.steps.enumerated() {
            // Time passes a second at a time, as the app ticks, and what a
            // tick brings (a heartbeat) is answered then, as in the app.
            var last: Harness.Pass?
            var lastSaid: String?  // the line its reaction said
            var lastTakes: [String] = []  // and its takes' texts
            func respond(_ views: [ViewEvent]) async {
                for view in views where view.wakesBrain {
                    ending.said = nil
                    ending.takes = []
                    guard let e = home.sync(execute: { harness.log.event(view.seq) }),
                          let record = await harness.respond(to: e) else { continue }
                    lastSaid = ending.said
                    lastTakes = ending.takes
                    last = record
                    let ran = record.actions.contains { $0.name == ReactAction.actionName && $0.result.ok }
                    let answers = record.answers
                    timeline.append(Pass(
                        atMs: clock.now - start, line: view.line,
                        reaction: ran ? Reaction(face: answers["react.mood"]?.choice ?? "none",
                                                 animation: ReactAction.animation(answers) ?? "none",
                                                 said: ending.said ?? "none") : nil,
                        loops: ran ? ReactAction.holds[ReactAction.loops(answers) - 1].name : nil,
                        mood: moodNow(), dropped: record.dropped,
                        offered: record.questions.first { $0.key == MoodAction.actionName }?.options.map(\.name) ?? [],
                        answer: answers[MoodAction.actionName]?.choice))
                }
            }
            ending.end = step.reaction.flatMap(Scenario.end) ?? .done
            while clock.now < start + step.atMs {
                clock.now = min(start + step.atMs, clock.now + 1000)
                await respond(home.sync { pipeline.tick(at: clock.now).views })
            }
            // Each input's view events get their passes before the next, as
            // the app's would once the brain answered.
            for input in Eval.inputs(step, at: clock.now) { await respond(home.sync { input(pipeline).views }) }
            let session = step.session ?? "s1"
            switch step.event {
            case "turn started":
                since = since ?? step.atMs
                open.insert(session)
            case "turn finished", "turn failed":
                open.remove(session)
                if open.isEmpty, let s = since {
                    working.append((s, step.atMs))
                    since = nil
                }
            default: break
            }
            guard let expect = step.expect else { continue }
            guard let record = last else {
                throw EvalError("\(scenario.file) step \(i + 1): expects a pass, but nothing woke the brain")
            }
            let react = record.answers["react.mood"]?.choice
            let ran = record.actions.contains { $0.name == ReactAction.actionName && $0.result.ok }
            checks.append(Check(step: i + 1, line: record.line ?? "", expected: expect, react: react,
                                animation: ran ? ReactAction.animation(record.answers) : nil,
                                feeling: ran ? ReactAction.feeling(record.answers) : nil,
                                about: ran ? ReactAction.about(record.answers) : nil,
                                kind: ran ? ReactAction.kind(record.answers).rawValue : nil,
                                said: ran ? lastSaid : nil, saidTakes: ran ? lastTakes : [],
                                loops: ran ? ReactAction.holds[ReactAction.loops(record.answers) - 1].name : nil,
                                mood: moodNow(), offered: timeline.last?.offered ?? [], dropped: record.dropped,
                                latencyMs: record.latencyMs))
        }
        if let s = since, let end = scenario.steps.last?.atMs { working.append((s, end)) }
        let runChecks = scenario.checks.map { Eval.judge($0, timeline: timeline, working: working, start: scenario.mood, graph: scenario.graph) } ?? []
        return Result(scenario: scenario.name, file: scenario.file, checks: checks, runChecks: runChecks, timeline: timeline)
    }

    /// The whole-run checks (internal/EVALS.md §3) against a run's passes, the
    /// spans its turn worked and the mood it started in.
    static func judge(_ c: Scenario.Checks, timeline: [Pass], working: [(Int64, Int64)],
                      start: String = MoodAction.initial, graph: MoodGraph.Version = .v2) -> [RunCheck] {
        var out: [RunCheck] = []
        let played = timeline.filter { $0.reaction != nil }
        func clock(_ ms: Int64) -> String { "\(ms / 60_000)m\(String(format: "%02d", ms / 1000 % 60))s" }
        func shown(_ r: ClosedRange<Int>) -> String {
            r.upperBound == Int.max ? "\(r.lowerBound) or more" : r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
        }
        if let limit = c.quietWorkingMs {
            var worst: (ms: Int64, from: Int64) = (0, 0)
            for (from, to) in working {
                let marks = [from] + played.map(\.atMs).filter { $0 > from && $0 < to } + [to]
                for (a, b) in zip(marks, marks.dropFirst()) where b - a > worst.ms { worst = (b - a, a) }
            }
            out.append(RunCheck(name: "max_quiet_working \(clock(limit))", passed: worst.ms <= limit,
                                detail: "the longest quiet stretch of work was \(clock(worst.ms)), from \(clock(worst.from))"))
        }
        if let limit = c.sameInARow {
            var best = (n: 0, what: "")
            var n = 0
            for (i, p) in played.enumerated() {
                n = i > 0 && played[i - 1].reaction == p.reaction ? n + 1 : 1
                if n > best.n { best = (n, p.reaction!.text) }
            }
            out.append(RunCheck(name: "max_same_in_a_row \(limit)", passed: best.n <= limit,
                                detail: best.n == 0 ? "no reactions" : "\(best.n) in a row (\(best.what))"))
        }
        var changes: [(at: Int64, from: String, to: String)] = []
        var mood = start  // the scenario's, calm by default (EVALS.md §1)
        for p in timeline where p.mood != mood {
            changes.append((p.atMs, mood, p.mood))
            mood = p.mood
        }
        let path = ([start] + changes.map(\.to)).joined(separator: " → ")
        if let range = c.moodChanges {
            out.append(RunCheck(name: "mood_changes \(shown(range))", passed: range.contains(changes.count),
                                detail: "\(changes.count): \(path)"))
        }
        if let limit = c.bounceMs {
            let bounce = zip(changes, changes.dropFirst()).first { a, b in b.to == a.from && b.at - a.at < limit }
            out.append(RunCheck(name: "no_mood_bounce_within \(clock(limit))", passed: bounce == nil,
                                detail: bounce.map { a, b in "\(a.from) → \(a.to) at \(clock(a.at)), back at \(clock(b.at))" } ?? path))
        }
        if let range = c.reactions {
            out.append(RunCheck(name: "reactions \(shown(range))", passed: range.contains(played.count),
                                detail: "\(played.count) of \(timeline.count) passes"))
        }
        if let least = c.variety {
            let kinds = Set(played.compactMap(\.reaction))
            out.append(RunCheck(name: "min_variety \(least)", passed: kinds.count >= least,
                                detail: "\(kinds.count): " + kinds.map(\.text).sorted().joined(separator: ", ")))
        }
        if c.onGraph {
            // Each pass's answer against what it offered, and each change
            // against the graph, from the mood before it.
            var before = start
            var wrong: String?
            for p in timeline where wrong == nil {
                if p.dropped?.hasPrefix("jev: no usable answer for \(MoodAction.actionName)") == true {
                    wrong = "at \(clock(p.atMs)): no usable mood answer"
                } else if p.dropped == nil, let answer = p.answer, !p.offered.contains(answer) {
                    wrong = "at \(clock(p.atMs)): answered \(answer), offered \(p.offered.joined(separator: "|"))"
                } else if p.mood != before, !(MoodGraph.moves(for: graph)[before]?.all.contains(p.mood) ?? false) {
                    wrong = "at \(clock(p.atMs)): \(before) → \(p.mood) isn't a move"
                }
                before = p.mood
            }
            out.append(RunCheck(name: "moves_on_graph", passed: wrong == nil,
                                detail: wrong ?? "\(timeline.count) passes: \(path)"))
        }
        return out
    }

    /// A run's passes, one line each: when, the line, what Boop did and the
    /// mood after.
    public static func timeline(_ result: Result) -> [String] {
        result.timeline.map { p in
            let t = "\(p.atMs / 60_000):\(String(format: "%02d", p.atMs / 1000 % 60))"
            let did = p.dropped.map { "dropped: \($0)" } ?? p.reaction.map { "\($0.text), \(p.loops ?? "once")" } ?? "none"
            return "    \(t)  \(p.line)  → \(did)  [\(p.mood)]"
        }
    }

    /// The device's `ended` that the app reads as `end` (`Reactions.end`):
    /// played to the end, cut by your tap (in progress while the pokes go
    /// on, done once they stop) or waited too long; nil for another end,
    /// which the fake device gives as it is.
    static func ended(_ end: Pending.End) -> Ended? {
        switch end {
        case .done: Ended(id: 1, how: .done)
        case .failed(Reactions.tapCut): Ended(id: 1, how: .cut, why: "tap")
        case .failed("waited too long"): Ended(id: 1, how: .skipped, why: "late")
        case .failed: nil
        }
    }

    /// How the reactions a step starts end, for the queue: nil leaves
    /// them in progress, kept here.
    final class Ending: @unchecked Sendable {
        var end: Pending.End? = .done
        var open: [Pending] = []
        /// The line the last pass's reaction said, if any, and its takes'
        /// texts.
        var said: String?
        var takes: [String] = []
    }

    /// A step as it reaches the pipeline: the hook events or pokes it
    /// stands for, in Claude's session (`s1` unless it says) in `landing`,
    /// each one input.
    public static func inputs(_ step: Scenario.Step, at now: Int64) -> [(Pipeline) -> Pipeline.Step] {
        let cwd = step.workspace.map { "/eval/landing/.worktrees/\($0)" } ?? "/eval/landing"
        let session = step.session ?? "s1"
        func hook(_ type: Event.Kind, _ phase: Event.Phase, _ specific: String,
                  _ data: [String: JSONValue] = [:]) -> (Pipeline) -> Pipeline.Step {
            { $0.agent(Event(at: now, source: .claude, type: type, phase: phase, specificType: specific, session: session,
                             cwd: cwd, data: data)) }
        }
        switch step.event {
        case "turn started": return [hook(.turn, .start, "UserPromptSubmit", step.prompt.map { ["prompt": .string($0)] } ?? [:])]
        case "turn finished": return [hook(.turn, .end, "Stop", ["outcome": "done"].merging(step.message.map { ["message": .string($0)] } ?? [:]) { a, _ in a })]
        case "turn failed": return [hook(.turn, .end, "StopFailure", ["outcome": "failed", "error": .string(step.error ?? "api_error")])]
        case "command":
            var end: [String: JSONValue] = ["tool": "Bash", "failed": .bool(step.failed ?? false)]
            if let topic = step.topic { end["topic"] = .string(topic) }
            if step.failed == true { end["error"] = "exit_code" }
            var start: [String: JSONValue] = ["tool": "Bash"]
            if let topic = step.topic { start["topic"] = .string(topic) }
            return [hook(.tool, .start, "PreToolUse", start),
                    hook(.tool, .end, step.failed == true ? "PostToolUseFailure" : "PostToolUse", end)]
        case "poke": return [{ $0.poke(at: now) }]
        case "pokes": return (0..<4).map { _ in { $0.poke(at: now) } }
        case "said": return [{ $0.said(step.words ?? "", by: .device, at: now) }]
        // What the presence detector would decide: you
        // lock the screen and leave now, and later unlock it.
        case "away": return [{ $0.presence(Event(at: now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                                 data: ["since": .int(now)])) }]
        case "back": return [{ $0.presence(Event(at: now, source: .mac, type: .presence, phase: .end, specificType: "unlocked")) }]
        default: return []  // wait
        }
    }

    /// One scenario's runs, readably: its verdict, and each failing step
    /// once.
    public static func report(_ runs: [Result], story: String? = nil, gap: String? = nil) -> [String] {
        guard let first = runs.first else { return [] }
        let passed = runs.filter(\.passed).count
        let tally = runs.count > 1 ? "  (\(passed)/\(runs.count) runs)" : ""
        let verdict = passed == runs.count ? (gap == nil ? "pass  " : "pass  (gap closed: take out its gap) ") : gap == nil ? "FAIL  " : "GAP   "
        var lines = [verdict + "\(first.file)  \(first.scenario)\(tally)"]
        if passed < runs.count, let gap { lines.append("  gap: \(gap)") }
        if passed < runs.count, let story { lines.append("  case: \(story)") }
        var seen: Set<String> = []
        for r in runs {
            for c in r.checks where !c.passed && seen.insert(c.summary).inserted { lines.append(c.summary) }
            for c in r.runChecks where !c.passed && seen.insert(c.summary).inserted { lines.append(c.summary) }
        }
        return lines
    }

    /// How many scenarios passed in every run: `7/10 passed`, and how
    /// many of the rest are known gaps.
    public static func summary(_ results: [[Result]], gaps: Int = 0) -> String {
        "\(results.filter { $0.allSatisfy(\.passed) }.count)/\(results.count) passed" + (gaps > 0 ? " (\(gaps) known gaps failed)" : "")
    }
}

/// The eval's clock, moved step by step.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int64
    init(_ ms: Int64) { self.ms = ms }
    var now: Int64 {
        get { lock.withLock { ms } }
        set { lock.withLock { ms = newValue } }
    }
}
