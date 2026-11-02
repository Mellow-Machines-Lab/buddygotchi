import BoopKit
import Foundation
import MellowHarness
import LinkKit

/// The harness evals (internal/EVALS.md): scenarios of hook-level steps on a
/// virtual clock, run through a fresh core, the real harness and the real
/// outputs, each pass checked against what Jev should answer. They ask Jev,
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
        /// Whose step it is: Claude's unless it says `codex`.
        public var agent: Event.Source?
        /// A command: its topic, and whether it failed.
        public var topic: String?
        /// A `command`'s program and which half of it: `start` or `end`, else both.
        public var program: String?
        public var half: String?
        public var failed: Bool?
        /// A failed turn's error class.
        public var error: String?
        /// What you asked, on a turn start, and the agent's last message,
        /// on a finish. Each reaches Jev as its reading: counted, and
        /// labelled with `labels` (`reading` in the file), which stand in
        /// for Apple Intelligence's.
        public var prompt: String?
        public var message: String?
        public var labels: PromptIntake.Labels?
        /// What you said to Boop, for `said`.
        public var words: String?
        /// How many pokes a `pokes` step makes, 4 unless it says.
        public var count: Int?
        /// Which helper a `helper started` or `helper returned` step is,
        /// `h1` unless it says.
        public var helper: String?
        /// What a `gesture` step did to the board: `stroke`, `nose`,
        /// `dizzy`… (render::Gesture's names, `facedown`, and `dismiss`, a
        /// finger held on the needs-you screen).
        public var kind: String?
        /// How an ask answered ends: a, b, touch or ignored.
        public var pick: String?
        /// A `to-do list` step's list, as `3/7`: done, of all.
        public var todos: StateSnapshot.Todo?
        /// How a reaction this step's passes start ends: `done` (the
        /// default), `in progress` (it never ends), or `failed: <why>`.
        public var reaction: String?
        /// What the pass should come to; nil checks nothing. A step with an
        /// expectation must wake the brain.
        public var expect: Expectation?
        /// The expectation's sets in the file's order, each value as
        /// written: the expect brain answers the first of each.
        public var expectOrder: [String: [String]] = [:]
        /// The step's own answers for the expect brain, one choice a
        /// question, as a demo's brain step has them.
        public var brain: [String: String]?
        /// Whether its passes are checked, so Jev answers them at every level.
        public var asksJev: Bool { expect?.wantsAPass ?? false }
    }

    /// What a pass should come to: each a set of acceptable values, `none`
    /// included where staying quiet or saying nothing is fine.
    public struct Expectation: Sendable, Equatable {
        /// Jev's `react.face` pick: `none` or a mood's face.
        public var react: Set<String>?
        /// The move the reaction played (`react.move`'s pick: a finish, a
        /// wake-up or a notice at an event, the reply to what you said,
        /// `huh` below the floor), or `none` when it played none or Boop
        /// didn't react.
        public var move: Set<String>?
        /// How big the moment was (`react.intensity`'s pick), or `none` when
        /// Boop didn't react.
        public var intensity: Set<String>?
        /// What it asked to say (`say`'s pick, when it reached the floor: a
        /// feeling, `swear` or a topic), or `none`.
        public var say: Set<String>?
        /// A take Boop said, by its text as the bubble shows it (`Tsk...`):
        /// the step passes when any of the `say`'s takes is one of these;
        /// with `some`, when it said anything; with `none`, when it said
        /// nothing.
        public var said: Set<String>?
        /// The mood after the pass.
        public var mood: Set<String>?
        /// Exactly the options the pass's mood question offered: staying
        /// in the mood it had, and its moves on the graph.
        public var offered: Set<String>?
        /// The thread a `press` opened on the Mac, as `agent thread`
        /// (`claude docs`): checked with no pass, since a press wakes no
        /// brain.
        public var opens: Set<String>?
        /// What the screen shows after the step, from the core's `state`,
        /// with no pass: how many sessions sit idle, how many helpers
        /// work (each a set of counts), and tags that must all be on.
        public var idle: Set<String>?
        public var helpers: Set<String>?
        public var when: Set<String>?
        /// Whether the needs-you screen shows (`shown`) or not (`none`), and
        /// the working agent's to-do list (`3/7`, or `none`).
        public var needs: Set<String>?
        public var todo: Set<String>?
        /// What Boop is busy with after the step (`asleep`, `idle`, `working`).
        public var doing: Set<String>?
        /// Whether a pass of the step, a check-in's on the way to it
        /// included, told the dream (`told`) or none did (`none`).
        public var dream: Set<String>?
        /// The sign the reaction held up: `some` for any, `none` for none,
        /// or words any of which it says (in any case: `still broken`
        /// passes "still broken :(").
        public var sign: Set<String>?

        /// Whether a sign that says `caption` (nil for none) is one of
        /// `wanted`: `some` for any, `none` for none, or words it says, in
        /// any case.
        public static func sign(_ wanted: some Collection<String>, says caption: String?) -> Bool {
            guard let caption else { return wanted.contains("none") }
            return wanted.contains { $0 == "some" || caption.range(of: $0, options: .caseInsensitive) != nil }
        }
        /// Whether any of it is about the screen.
        public var wantsTheScreen: Bool { idle != nil || helpers != nil || when != nil || needs != nil || todo != nil || doing != nil }
        /// Whether any of it is about a pass.
        public var wantsAPass: Bool { checksAChoice || offered != nil || dream != nil }
        /// Whether it checks one of Jev's own choices, which a feel scenario
        /// leaves to the judge.
        var checksAChoice: Bool {
            react != nil || move != nil || intensity != nil || say != nil || said != nil || mood != nil || sign != nil
        }

        public init(react: Set<String>? = nil, move: Set<String>? = nil, intensity: Set<String>? = nil, say: Set<String>? = nil,
                    said: Set<String>? = nil, mood: Set<String>? = nil, offered: Set<String>? = nil, opens: Set<String>? = nil) {
            self.react = react
            self.move = move
            self.intensity = intensity
            self.say = say
            self.said = said
            self.mood = mood
            self.offered = offered
            self.opens = opens
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
        /// face, move and what it said.
        public var sameInARow: Int?
        /// `mood_changes`: how many times the mood may change in the run.
        public var moodChanges: ClosedRange<Int>?
        /// `no_mood_bounce_within`: a mood may not change back to the one it
        /// just left sooner than this.
        public var bounceMs: Int64?
        /// `reactions`: how many reactions the run may play.
        public var reactions: ClosedRange<Int>?
        /// `min_variety`: the fewest different reactions (face, move and
        /// what it said) the run must play.
        public var variety: Int?
        /// `words_said`: the share of the reactions played that said
        /// something, as a range (`0.5-`).
        public var wordsSaid: ClosedRange<Double>?
        /// `moves_on_graph`: every pass's mood answer was one of the
        /// options it offered, and every mood change was a move on the
        /// mood graph.
        public var onGraph = false
        /// `moods_seen`: moods the run must reach at some pass, like
        /// `lonely`; a mood that comes and fades between two steps still
        /// counts.
        public var moodsSeen: [String] = []
        /// `signs_seen`: signs the run must hold up at some pass, any one
        /// of them (`"fav snack?|hat or bow?"`): for what Jev does now and
        /// then, not at a given step.
        public var signsSeen: [String] = []

        public init() {}

        /// Only the checks a run can fail without Jev choosing: the quiet
        /// while working, and moves on the mood graph.
        var withoutChoices: Checks {
            var kept = Checks()
            kept.quietWorkingMs = quietWorkingMs
            kept.onGraph = onGraph
            return kept
        }

        static let keys = ["max_quiet_working", "max_same_in_a_row", "mood_changes", "no_mood_bounce_within",
                           "reactions", "min_variety", "words_said", "moves_on_graph", "moods_seen", "signs_seen"]
    }

    public var name: String
    /// The situation and what Boop should do in it, in plain words and
    /// with no harness terms, so the steps can be rewritten to fit it when
    /// the harness changes (the file's `case`).
    public var story: String
    public var why: String
    /// Boop's character, not a tuning target: runs 3 times at the full level,
    /// and `boopdev eval --always` runs only these.
    public var always: Bool
    /// It checks the code's rules, not Jev's choices: it runs only with
    /// the expect brain (`--scripted`, and the unit tests), and a Jev run
    /// leaves it out.
    public var scripted: Bool
    /// How many runs it gets when `--runs` doesn't say, at any level, if
    /// not the default (`Eval.runs`).
    public var runs: Int?
    public var checks: Checks?
    /// A feel scenario's brief, for the judge to read a run against: it has
    /// no exact checks on Jev's choices. With none, the scenario is a must.
    public struct Brief: Sendable {
        public var judge: String
        public var reasonable: String
        public var unreasonable: String
    }
    public var brief: Brief?
    /// A known gap: why Boop can't pass this today, and what would fix it.
    /// Its failures are reported but don't fail the eval, and the report
    /// says when it passes after all.
    public var gap: String?
    /// How much it says, chosen in Settings, told in CONTEXT's Talk row
    /// and held in code, as in the app: normal unless the file says.
    public var talk: Talk
    /// The mood the run starts in, as the dashboard would set it just
    /// before: calm, the resting mood, unless the file says.
    public var mood: String
    public var steps: [Step]
    public var file: String
    /// When the run starts, in ms since 1970 (`start`, a UTC date and time,
    /// `2026-10-31T09:00`): nil for `Replay.defaultStart`, a Wednesday at
    /// 14:00.
    public var start: Int64?
    /// The day Boop hatched, `yyyy-MM-dd`, for its milestone days: nil for
    /// none.
    public var hatched: String?
    /// The written memory the run starts with (`memory`): its notes, as
    /// `memory.md` writes them without the id (`work · 2026-10-25 · "api"
    /// kept failing`), and Recently's lines (`2026-10-25 · a long day`).
    public var memory = WrittenMemory()

    public static let events = ["wish", "turn started", "command", "turn finished", "turn failed", "poke", "hush", "pokes", "said",
                                "away", "back", "lock", "unlock", "session started", "compact", "needs you", "answered", "press", "helper started", "helper returned", "gesture", "edit",
                                "to-do list", "wait", "ask answered"]

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
        if let judge = o["judge"] as? String {
            guard let reasonable = o["reasonable"] as? String, let unreasonable = o["unreasonable"] as? String else {
                throw bad("a feel scenario needs judge, reasonable and unreasonable")
            }
            guard o["case"] == nil, o["why"] == nil, o["always"] == nil, o["gap"] == nil else {
                throw bad("a feel scenario has its brief, with no case, why, always or gap")
            }
            brief = Brief(judge: judge, reasonable: reasonable, unreasonable: unreasonable)
        }
        guard let name = o["name"] as? String, let story = brief?.judge ?? (o["case"] as? String),
              let why = brief != nil ? "" : (o["why"] as? String), let raw = o["steps"] as? [[String: Any]]
        else { throw bad("needs name, case, why and steps") }
        let unknownKeys = Set(o.keys).subtracting(["name", "judge", "reasonable", "unreasonable", "case", "why", "always", "scripted", "runs", "gap", "talk", "mood", "checks", "steps", "start", "hatched", "memory"])
        guard unknownKeys.isEmpty else { throw bad("unknown key \(unknownKeys.sorted().joined(separator: ", "))") }
        self.name = name
        self.story = story
        self.why = why
        always = o["always"] as? Bool ?? false
        scripted = o["scripted"] as? Bool ?? false
        if always, scripted { throw bad("a scripted scenario asks Jev nothing, so it isn't always") }
        if let t = o["start"] {
            guard let text = t as? String, let ms = Scenario.date(text) else { throw bad("start is a UTC date and time, like 2026-10-31T09:00") }
            start = ms
        }
        if let m = o["memory"] {
            guard let m = m as? [String: Any], Set(m.keys).isSubset(of: ["notes", "recently"]),
                  let notes = (m["notes"] ?? []) as? [String], let recently = (m["recently"] ?? []) as? [String] else {
                throw bad("memory has notes and recently, lists of lines")
            }
            guard let read = WrittenMemory.from(notes: notes, recently: recently) else {
                throw bad("memory's lines are like work · 2026-10-25 · the note, and 2026-10-25 · the day")
            }
            memory = read
        }
        if let h = o["hatched"] {
            guard let day = h as? String, LocalTime.isDay(day) else { throw bad("hatched is a day, like 2026-09-01") }
            hatched = day
        }
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
            func range<T: LosslessStringConvertible & Comparable>(_ key: String, within bounds: ClosedRange<T>, like: String = "1-3, 2- or -4") throws -> ClosedRange<T>? {
                guard let v = c[key] else { return nil }
                guard let t = v as? String, let r = Scenario.range(t, within: bounds) else { throw bad("checks.\(key) is like \(like)") }
                return r
            }
            var checks = Checks()
            checks.quietWorkingMs = try time("max_quiet_working")
            checks.sameInARow = try count("max_same_in_a_row")
            checks.moodChanges = try range("mood_changes", within: 0...Int.max)
            checks.bounceMs = try time("no_mood_bounce_within")
            checks.reactions = try range("reactions", within: 0...Int.max)
            checks.variety = try count("min_variety")
            checks.wordsSaid = try range("words_said", within: 0...1.0, like: "0.5- or 0.2-0.8")
            if let v = c["moves_on_graph"] {
                guard let on = v as? Bool, on else { throw bad("checks.moves_on_graph is true") }
                checks.onGraph = true
            }
            if let v = c["moods_seen"] {
                guard let text = v as? String else { throw bad("checks.moods_seen is like \"lonely|sad\"") }
                checks.moodsSeen = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let unknown = checks.moodsSeen.filter { MoodGraph.mood($0) == nil }
                guard unknown.isEmpty else { throw bad("checks.moods_seen has \(unknown.joined(separator: ", ")), not a mood") }
            }
            if let v = c["signs_seen"] {
                guard let text = v as? String, !text.isEmpty else { throw bad("checks.signs_seen is like \"fav snack?|hat or bow?\"") }
                checks.signsSeen = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            self.checks = checks
        }
        talk = try (o["talk"] as? String).map {
            guard let t = Talk(rawValue: $0) else { throw bad("talk is quiet, normal or chatty") }
            return t
        } ?? .default
        let graphMoods = MoodGraph.moods
        mood = try (o["mood"] as? String).map {
            guard graphMoods.contains($0) else { throw bad("mood is one of \(graphMoods.joined(separator: ", "))") }
            return $0
        } ?? MoodOutput.initial
        steps = try raw.enumerated().map { i, s in
            func badStep(_ why: String) -> Error { bad("step \(i + 1): \(why)") }
            guard let event = s["event"] as? String, Scenario.events.contains(event) else {
                throw badStep("event is one of \(Scenario.events.joined(separator: ", "))")
            }
            guard let at = s["at"] as? String, let atMs = Scenario.ms(at) else { throw badStep("at is like 0m, 90s or 2m30s") }
            var step = Step(event: event, atMs: atMs)
            step.workspace = s["workspace"] as? String
            step.session = s["session"] as? String
            if let agent = s["agent"] {
                guard let a = (agent as? String).flatMap(Event.Source.init(rawValue:)), [.claude, .codex].contains(a) else {
                    throw badStep("agent is claude or codex")
                }
                if a == .codex, event == "turn failed" { throw badStep("turn failed is Claude's: Codex has no hook for it") }
                step.agent = a
            }
            for (key, only) in ["prompt": ["turn started"], "reading": ["turn started", "turn finished"], "message": ["turn finished"],
                                "count": ["pokes", "edit"], "todos": ["to-do list"]]
            where s[key] != nil && !only.contains(event) {
                throw badStep("\(key) is only for \(only.joined(separator: " and "))")
            }
            step.topic = s["topic"] as? String
            step.program = s["program"] as? String
            step.half = s["half"] as? String
            step.failed = s["failed"] as? Bool
            step.error = s["error"] as? String
            step.prompt = s["prompt"] as? String
            step.message = s["message"] as? String
            if let r = s["reading"] {
                guard let r = r as? [String: Any] else { throw badStep("reading is an object") }
                let finish = event == "turn finished"
                if finish, step.message == nil { throw badStep("a finish's reading is its message's, and it has none") }
                do {
                    step.labels = finish ? .message(try MessageReading.Labels(json: r)) : .prompt(try PromptReading.Labels(json: r))
                } catch { throw badStep("\(error)") }
            }
            step.words = s["words"] as? String
            step.helper = s["helper"] as? String
            step.kind = s["kind"] as? String
            if event == "gesture", step.kind.flatMap({ Touch(rawValue: $0)?.line() }) == nil { throw badStep("gesture needs a kind the board makes") }
            if event == "ask answered" {
                step.pick = s["pick"] as? String ?? "a"
                guard ["a", "b", "touch", Asks.ignored].contains(step.pick!) else { throw badStep("an ask's pick is a, b, touch or ignored") }
            }
            if event == "said", step.words?.isEmpty != false { throw badStep("said needs words") }
            if event == "to-do list" {
                guard let text = s["todos"] as? String, let list = StateSnapshot.Todo(text: text) else { throw badStep("to-do list needs todos, like 3/7") }
                step.todos = list
            }
            if let c = s["count"] {
                guard let n = c as? Int, n >= 1 else { throw badStep("count is for pokes, 1 or more") }
                step.count = n
            }
            if let reaction = s["reaction"] {
                guard let text = reaction as? String, Scenario.end(text) != nil else {
                    throw badStep("reaction is done, in progress or failed: <why>")
                }
                step.reaction = text
            }
            if let b = s["brain"] {
                guard let answers = b as? [String: String] else { throw badStep("brain is question keys to choices, both strings") }
                step.brain = answers
            }
            if let e = s["expect"] as? [String: Any] {
                // What `!` takes away from: every value a key may be.
                // `none` first, as the expect brain answers with the first.
                let every: [String: [String]] = ["react": ["none"] + CharacterPack.active.moods.map(\.id), "mood": graphMoods,
                                                 "say": ["none"] + MomentOutput.says.map(\.name)]
                func set(_ key: String) throws -> Set<String>? {
                    guard let v = e[key] else { return nil }
                    guard let text = v as? String else { throw badStep("expect.\(key) is like \"proud|excited\"") }
                    // `!none`: anything but these, of what the key may be.
                    let but = text.hasPrefix("!")
                    let values = text.dropFirst(but ? 1 : 0).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard but else {
                        step.expectOrder[key] = values
                        return Set(values)
                    }
                    guard let all = every[key] else { throw badStep("expect.\(key) can't take !: only \(every.keys.sorted().joined(separator: ", ")) can") }
                    guard Set(values).isSubset(of: all) else { throw badStep("expect.\(key) takes away \(values.joined(separator: "|")), not all of them its values") }
                    step.expectOrder[key] = all.filter { !values.contains($0) }
                    return Set(step.expectOrder[key] ?? [])
                }
                let keys = ["react", "move", "intensity", "say", "said", "mood", "offered", "opens", "idle",
                            "helpers", "when", "needs", "todo", "doing", "dream", "sign"]
                let unknown = Set(e.keys).subtracting(keys)
                guard unknown.isEmpty else { throw badStep("expect has only \(keys.joined(separator: ", "))") }
                step.expect = Expectation(react: try set("react"), move: try set("move"), intensity: try set("intensity"), say: try set("say"),
                                          said: try set("said"), mood: try set("mood"), offered: try set("offered"))
                let opens = try set("opens"), idle = try set("idle"), helpers = try set("helpers"), when = try set("when")
                step.expect?.opens = opens
                step.expect?.idle = idle
                step.expect?.helpers = helpers
                step.expect?.when = when
                let needs = try set("needs"), todo = try set("todo")
                guard (needs ?? []).isSubset(of: ["shown", "none"]) else { throw badStep("expect.needs is shown or none") }
                guard (todo ?? []).allSatisfy({ $0 == "none" || StateSnapshot.Todo(text: $0) != nil }) else { throw badStep("expect.todo is like 3/7, or none") }
                step.expect?.needs = needs
                let doing = try set("doing")
                step.expect?.doing = doing
                step.expect?.todo = todo
                let dream = try set("dream")
                guard (dream ?? []).isSubset(of: ["told", "none"]) else { throw badStep("expect.dream is told or none") }
                step.expect?.dream = dream
                let sign = try set("sign")
                step.expect?.sign = sign
                let unknownTags = (when ?? []).subtracting(Tags.all)
                guard unknownTags.isEmpty else { throw badStep("expect.when has \(unknownTags.sorted().joined(separator: ", ")), not a tag") }
                for (key, values, known) in [("say", step.expect?.say, MomentOutput.says.map(\.name)),
                                             ("intensity", step.expect?.intensity, MomentOutput.sizeOptions.map(\.name)),
                                             ("move", step.expect?.move, (MomentOutput.animations + MomentOutput.replies).map(\.name) + ["unhush", MomentOutput.wave])] {
                    let unknown = (values ?? []).subtracting(known + ["none"])
                    guard unknown.isEmpty else { throw badStep("expect.\(key) has \(unknown.sorted().joined(separator: ", ")), not one of \(known.joined(separator: ", "))") }
                }
                let texts = Set(Take.all.map(\.text))
                let unsaid = (step.expect?.said ?? []).subtracting(texts.union(["none", "some"]))
                guard unsaid.isEmpty else { throw badStep("expect.said has \(unsaid.sorted().joined(separator: ", ")), not a take's text") }
                // A face may be any mood's; a mood, or what's offered, only a lasting one's.
                let faces = CharacterPack.active.moods.map(\.id) + ["none"]
                for (key, values) in [("react", step.expect?.react), ("mood", step.expect?.mood), ("offered", step.expect?.offered)] {
                    let unknown = (values ?? []).subtracting(key == "react" ? faces : graphMoods)
                    guard unknown.isEmpty else { throw badStep("expect.\(key) has \(unknown.sorted().joined(separator: ", ")), not \(key == "react" ? "a face" : "a lasting mood")") }
                }
            }
            return step
        }
        if brief != nil {
            if let i = steps.firstIndex(where: { $0.expect?.checksAChoice == true }) { throw bad("step \(i + 1): a feel scenario checks no choice of Jev's; the judge reads them") }
        } else {
            guard checks != nil || steps.contains(where: { $0.expect != nil }) else { throw bad("expects nothing") }
        }
    }

    /// `1-3`, `2-` (2 or more), `-4` (4 at most) or `3`, of counts or of
    /// shares (`0.5-`, half or more), within `bounds`.
    static func range<T: LosslessStringConvertible & Comparable>(_ text: String, within bounds: ClosedRange<T>) -> ClosedRange<T>? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 { return T(parts[0]).flatMap { bounds.contains($0) ? $0...$0 : nil } }
        guard parts.count == 2, !(parts[0].isEmpty && parts[1].isEmpty),
              let low = parts[0].isEmpty ? bounds.lowerBound : T(parts[0]),
              let high = parts[1].isEmpty ? bounds.upperBound : T(parts[1]),
              bounds.contains(low), bounds.contains(high), low <= high else { return nil }
        return low...high
    }

    /// `2026-10-31T09:00`, in UTC, as ms since 1970.
    static func date(_ text: String) -> Int64? { DemoScript.date(text, timeZone: TimeZone(identifier: "UTC")!) }

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
        /// What happened: the react.face pick, the move played, how big,
        /// what it asked to say, the `say` and its takes, the mood after.
        public var react: String?
        public var move: String?
        public var intensity: String?
        public var say: String?
        public var said: String?
        public var saidTakes: [String] = []
        /// The sign the reaction held up.
        public var sign: String?
        public var mood: String
        /// What the pass's mood question offered.
        public var offered: [String] = []
        public var dropped: String?
        public var latencyMs: Int
        /// What a press opened, `agent thread`, for `opens`.
        public var opened: String?
        /// What the screen showed: the idle and helper counts, the tags,
        /// whether the needs-you screen showed, and the to-do list (`3/7`, or
        /// `none`).
        public var screen: (idle: Int, helpers: Int, when: [String], needs: Bool, todo: String, doing: String)?
        /// Whether the pass's line told the dream.
        public var told = false

        public var passed: Bool {
            guard dropped == nil else { return false }
            if let o = expected.opens { return o.contains(opened ?? "nothing") }
            if let shown = screen {
                if let i = expected.idle, !i.contains("\(shown.idle)") { return false }
                if let h = expected.helpers, !h.contains("\(shown.helpers)") { return false }
                if let w = expected.when, !w.isSubset(of: shown.when) { return false }
                if let n = expected.needs, !n.contains(shown.needs ? "shown" : "none") { return false }
                if let t = expected.todo, !t.contains(shown.todo) { return false }
                if let d = expected.doing, !d.contains(shown.doing) { return false }
                return true
            }
            if let r = expected.react, !r.contains(react ?? "none") { return false }
            if let m = expected.move, !m.contains(move ?? "none") { return false }
            if let i = expected.intensity, !i.contains(intensity ?? "none") { return false }
            if let s = expected.say, !s.contains(say ?? "none") { return false }
            if let s = expected.said, !(saidTakes.isEmpty ? s.contains("none") : s.contains("some") || saidTakes.contains(where: s.contains)) {
                return false
            }
            if let m = expected.mood, !m.contains(mood) { return false }
            if let d = expected.dream, !d.contains(told ? "told" : "none") { return false }
            if let s = expected.sign, !Scenario.Expectation.sign(s, says: sign) { return false }
            if let o = expected.offered, o != Set(offered) { return false }
            return true
        }

        public var summary: String {
            let want = [expected.react.map { "react \($0.sorted().joined(separator: "|"))" },
                        expected.move.map { "move \($0.sorted().joined(separator: "|"))" },
                        expected.intensity.map { "intensity \($0.sorted().joined(separator: "|"))" },
                        expected.say.map { "say \($0.sorted().joined(separator: "|"))" },
                        expected.said.map { "said \($0.sorted().joined(separator: "|"))" },
                        expected.mood.map { "mood \($0.sorted().joined(separator: "|"))" },
                        expected.offered.map { "offered \($0.sorted().joined(separator: "|"))" },
                        expected.opens.map { "opens \($0.sorted().joined(separator: "|"))" },
                        expected.idle.map { "idle \($0.sorted().joined(separator: "|"))" },
                        expected.helpers.map { "helpers \($0.sorted().joined(separator: "|"))" },
                        expected.when.map { "when \($0.sorted().joined(separator: " and "))" },
                        expected.needs.map { "needs \($0.sorted().joined(separator: "|"))" },
                        expected.todo.map { "todo \($0.sorted().joined(separator: "|"))" },
                        expected.dream.map { "dream \($0.sorted().joined(separator: "|"))" },
                        expected.sign.map { "sign \($0.sorted().joined(separator: "|"))" }].compactMap { $0 }
            let got = opened.map { "opened \($0)" }
                ?? screen.map { "idle \($0.idle), helpers \($0.helpers), when \($0.when.joined(separator: " ")), needs \($0.needs ? "shown" : "none"), todo \($0.todo), doing \($0.doing)" }
                ?? dropped.map { "dropped: \($0)" }
                ?? "react \(react ?? "none"), move \(move ?? "none"), intensity \(intensity ?? "none"), say \(say ?? "none"), said \(said ?? "none"), mood \(mood)"
                + (expected.offered == nil ? "" : ", offered \(offered.sorted().joined(separator: "|"))")
                + (expected.sign == nil ? "" : ", sign \(sign ?? "none")")
            return "  step \(step): \(line)\n    wanted \(want.joined(separator: ", ")); got \(got)"
        }
    }

    /// A reaction as the person sees it; two are the same when all of it
    /// is, however big each was.
    public struct Reaction: Sendable, Hashable {
        public var face: String
        public var move: String
        /// The take's text, or `none`.
        public var said: String
        public var text: String {
            face + (move == "none" ? "" : " \(move)") + (said == "none" ? "" : " \"\(said)\"")
        }
    }

    /// One pass of a run, checked or not, for the whole-run checks and the
    /// timeline.
    public struct Pass: Sendable {
        /// Virtual ms since the run started.
        public var atMs: Int64
        public var line: String
        /// What played, if Boop reacted, and how big.
        public var reaction: Reaction?
        public var intensity: String?
        /// The mood after the pass.
        public var mood: String
        public var dropped: String?
        /// What the mood question offered, and Jev's answer to it.
        public var offered: [String] = []
        public var answer: String?
        /// The sign its reaction held up, if any.
        public var sign: String?
        /// The brain that answered it.
        public var brain: String?
        /// The step it came on, from 1, a check-in's on the way to it included.
        public var step = 0
        /// The narration its reaction carried, if any.
        public var narration: String?
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
    /// Whether the whole-run checks on Jev's own choices (its variety, its
    /// mood's changes, what it says) are judged: not with a scripted brain.
    public var judgesChoices: Bool { !(brain is ScenarioBrain) }
    /// Whether the expect brain answers every pass but those of a step that
    /// expects one, which `brain` answers (the quick level).
    public var scriptsSetup = false
    /// Reads each prompt and last message in place of its `reading`: Apple
    /// Intelligence for `--labeler apple`, so a run checks it too.
    public var labeler: (any PromptLabeler)?
    /// Hears each pass of a run with the step it came on (from 1), a
    /// check-in's on the way to the step included: `boopdev prompts`.
    public var onPass: ((_ step: Int, _ pass: Harness.Pass) -> Void)?

    public init(brain: any Brain, steering: Steering) {
        self.brain = brain
        self.steering = steering
    }

    /// How much of the eval a run asks Jev (internal/EVALS.md §2).
    public enum Level: String, CaseIterable, Sendable {
        /// The must scenarios; Jev answers only the passes of steps that
        /// expect one, unless whole-run checks read them all.
        case quick
        /// Every scenario once, every pass to Jev.
        case standard
        /// Standard, with `always` scenarios 3 times.
        case full
    }

    /// How `level` runs a scenario against Jev; nil when it leaves the
    /// scenario out.
    public struct Plan: Sendable, Equatable {
        /// How many runs: `--runs`, else its own `runs`, else 3 at the full
        /// level for an `always` one, Boop's character, and 1 for the rest.
        public var runs: Int
        /// Whether the expect brain answers its setup. Whole-run checks and
        /// the judge read every pass, so those scenarios play in full.
        public var scriptsSetup: Bool
        /// Whether a failed run gets its one re-run: a must's does, to
        /// confirm before it blocks, unless `--runs` or its own runs repeat it.
        public var rerunsOnFailure: Bool
        /// `--scripted`: each scenario once, with the expect brain.
        public static let scripted = Plan(runs: 1, scriptsSetup: false, rerunsOnFailure: false)
    }

    /// The plan for a scenario at `level`. Quick leaves out a feel scenario
    /// unless `--only` named it, and a scripted scenario never goes to Jev.
    public static func plan(_ scenario: Scenario, level: Level, named: Bool, given: Int? = nil) -> Plan? {
        guard !scenario.scripted, level != .quick || scenario.brief == nil || named else { return nil }
        let runs = given ?? scenario.runs ?? (level == .full && scenario.always ? 3 : 1)
        return Plan(runs: runs,
                    scriptsSetup: level == .quick && scenario.checks == nil && scenario.brief == nil,
                    rerunsOnFailure: scenario.brief == nil && scenario.gap == nil && runs == 1)
    }

    /// One run as a line for the judge (internal/EVALS.md §2): the scenario,
    /// its brief, and per pass the line Jev read and what Boop did.
    public static func trajectory(_ result: Result, scenario: Scenario) -> [String: Any] {
        var out: [String: Any] = ["file": scenario.file, "name": scenario.name, "group": scenario.brief == nil ? "must" : "feel",
                                  "talk": scenario.talk.rawValue, "starts_in_mood": scenario.mood, "checks_passed": result.passed]
        if let b = scenario.brief {
            out["brief"] = ["judge": b.judge, "reasonable": b.reasonable, "unreasonable": b.unreasonable]
        }
        out["passes"] = result.timeline.map { p -> [String: Any] in
            var pass: [String: Any] = ["step": p.step, "at_s": p.atMs / 1000, "line": p.line, "mood": p.mood, "brain": p.brain ?? "none"]
            if let r = p.reaction {
                pass["face"] = r.face
                pass["move"] = r.move
                pass["said"] = r.said
                pass["size"] = p.intensity ?? "small"
            }
            if let sign = p.sign { pass["sign"] = sign }
            if let n = p.narration { pass["narration"] = n }
            if let d = p.dropped { pass["dropped"] = d }
            return pass
        }
        return out
    }

    /// About how many passes one run of a scenario asks a brain, counted with
    /// the expect brain, no key needed: all of them, and those of steps that
    /// expect one. A real run can differ by a pass or two, since what Jev
    /// answers can move what wakes it later.
    public struct Price: Sendable {
        public var all = 0
        public var expected = 0
    }

    public static func price(_ scenario: Scenario, steering: Steering) async throws -> Price {
        final class Tally: @unchecked Sendable { var price = Price() }
        let tally = Tally()
        var runner = Eval(brain: ExpectBrain(), steering: steering)
        runner.onPass = { step, pass in
            guard pass.held == nil else { return }
            tally.price.all += 1
            if scenario.steps[step - 1].asksJev { tally.price.expected += 1 }
        }
        _ = try await runner.run(scenario)
        return tally.price
    }

    /// One run of a scenario, from a fresh core and transcript, the mood
    /// in it.
    public func run(_ scenario: Scenario) async throws -> Result {
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let start = scenario.start ?? Replay.defaultStart
        let clock = VirtualClock(start)
        let rules = steering.rules(talk: scenario.talk)
        // Its agents are made up, and run all through it, their threads
        // never archived.
        let core = Core(config: .init(time: time, hatched: scenario.hatched), lastActiveDay: time.day(start),
                        isRunning: { _ in true }, archive: { _ in .open })
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
        // Memory, in memory: the day's tallies and the dream of everything
        // since the last, on the virtual clock, told the next time you show up.
        let remembers = Memory(store: try KeyValueStore(directory: nil), time: time)
        home.sync { remembers.attach(to: pipeline) }
        let (harness, mood) = Runtime.harness(
            pipeline: pipeline, steering: steering, reactions: reactions,
            queue: { reaction, pending in
                ending.said = reaction.say?.text
                ending.takes = reaction.say?.takes.map(\.text) ?? []
                ending.sign = reaction.sign
                ending.narration = reaction.reason
                guard let end = ending.end else { return ending.open.append(pending) }
                if let ended = Eval.ended(end) {
                    reactions.read(.ended(ended), pending).map(pending.finish)
                } else {
                    pending.finish(end)
                }
            }, talk: { scenario.talk }, memory: { scenario.memory.section(today: time.boopDay(clock.now)) },
            remembers: remembers, wall: { clock.now })
        if let url = debugLog {
            let writer = Runtime.debugLines(pipeline: pipeline, emit: { LineFile.append($0, to: url) })
            harness.onPass = { pass in writer.pass(pass, launchOptions: [:], at: clock.now) }
        }
        func moodNow() -> String { home.sync { MoodOutput.value(mood, harness.log.view(now: clock.now)) } }
        home.sync {
            harness.use(brain)
            // The mood it starts in, as the dashboard would set it just before.
            if scenario.mood != MoodOutput.initial {
                harness.force(mood, by: Runtime.forcedBy) {
                    MoodOutput.change(mood, to: scenario.mood, log: harness.log.view(now: clock.now))
                }
            }
        }

        var checks: [Check] = []
        var timeline: [Pass] = []
        // When any of the scenario's turns works, from the steps: [start, end].
        var working: [(Int64, Int64)] = []
        var since: Int64?
        var open: Set<String> = []
        let setup = scriptsSetup ? ExpectBrain() : nil
        for (i, step) in scenario.steps.enumerated() {
            // Time passes a second at a time, as the app ticks, and what a
            // tick brings (a check-in) is answered then, as in the app.
            var last: Harness.Pass?
            var lastSaid: String?  // what its reaction said
            var lastTakes: [String] = []  // and its takes' texts
            var lastSign: String?  // and the sign it held up
            var toldDream = false  // any pass of the step, a check-in's on the way included
            func respond(_ views: [ViewEvent]) async {
                for view in views where view.wakesBrain {
                    ending.said = nil
                    ending.takes = []
                    ending.sign = nil
                    ending.narration = nil
                    guard let e = home.sync(execute: { harness.log.event(view.seq) }),
                          let record = await harness.respond(to: e) else { continue }
                    lastSaid = ending.said
                    lastTakes = ending.takes
                    lastSign = ending.sign
                    last = record
                    onPass?(i + 1, record)
                    if view.facts["dream_day"] != nil { toldDream = true }
                    let ran = record.outputs.contains { $0.name == MomentOutput.outputName && $0.result.ok }
                    let answers = record.answers
                    timeline.append(Pass(
                        atMs: clock.now - start, line: view.line,
                        reaction: ran ? Reaction(face: answers[MomentOutput.emotionKey]?.choice ?? "none",
                                                 move: MomentOutput.move(answers) ?? "none",
                                                 said: ending.said ?? "none") : nil,
                        intensity: ran ? MomentOutput.size(answers).name : nil,
                        mood: moodNow(), dropped: record.dropped,
                        offered: record.questions.first { $0.key == MoodOutput.outputName }?.options.map(\.name) ?? [],
                        answer: answers[MoodOutput.outputName]?.choice, sign: ran ? ending.sign : nil, brain: record.brain, step: i + 1, narration: ran ? ending.narration : nil))
                }
            }
            ending.end = step.reaction.flatMap(Scenario.end) ?? .done
            // The expect brain answers the step's passes, a check-in's on
            // the way to it included, from the step.
            let scripted = (setup ?? brain) as? ScenarioBrain
            if let setup { home.sync { harness.use(step.asksJev ? brain : setup) } }
            scripted?.willRun(step, ahead: scenario.steps.dropFirst(i + 1).lazy.compactMap { $0.expectOrder["mood"] ?? $0.brain?[MoodOutput.outputName].map { [$0] } }.first ?? [])
            while clock.now < start + step.atMs {
                clock.now = min(start + step.atMs, clock.now + 1000)
                await respond(home.sync { pipeline.tick(at: clock.now).views })
            }
            // Each input's view events get their passes before the next, as
            // the app's would once the brain answered.
            var read = step
            if let labeler, let prompt = step.prompt {
                read.labels = await labeler.label(Scrubber.scrub(prompt), as: PromptText.self).map(PromptIntake.Labels.prompt)
            }
            if let labeler, let message = step.message {
                read.labels = await labeler.label(Scrubber.scrub(message), as: MessageText.self).map(PromptIntake.Labels.message)
            }
            for input in Eval.inputs(read, at: clock.now) { await respond(home.sync { input(pipeline).views }) }
            scripted?.willRun(nil, ahead: [])
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
            // A step that writes its brain's answers wakes the brain, as an expecting one does.
            if brain is ScenarioBrain, step.brain != nil, last == nil {
                throw EvalError("\(scenario.file) step \(i + 1): has brain answers, but nothing woke the brain")
            }
            guard let expect = step.expect else { continue }
            if expect.wantsTheScreen {
                // What the screen shows now: the core's state, with no pass.
                let shown = home.sync { core.snapshot(at: clock.now) }
                var check = Check(step: i + 1, line: "the screen", expected: Scenario.Expectation(), mood: moodNow(), latencyMs: 0)
                check.expected.idle = expect.idle
                check.expected.helpers = expect.helpers
                check.expected.when = expect.when
                check.expected.needs = expect.needs
                check.expected.todo = expect.todo
                check.expected.doing = expect.doing
                check.screen = (shown.idle, shown.helpers, shown.when, shown.attn != nil, shown.todo?.text ?? "none", shown.doing)
                checks.append(check)
                if !expect.wantsAPass, expect.opens == nil { continue }
            }
            if let opens = expect.opens {
                // What the press opened: the core's record of it, this step's.
                let did = home.sync { harness.log.events.last { $0.action == Core.openThread && $0.at == clock.now } }
                let got = did.map { "\($0["agent"]?.string ?? "") \($0["thread"]?.string ?? "")" } ?? "nothing"
                checks.append(Check(step: i + 1, line: "a press", expected: Scenario.Expectation(opens: opens), mood: moodNow(),
                                    latencyMs: 0, opened: got))
                if !expect.wantsAPass { continue }
            }
            guard let record = last else {
                throw EvalError("\(scenario.file) step \(i + 1): expects a pass, but nothing woke the brain")
            }
            let react = record.answers[MomentOutput.emotionKey]?.choice
            let ran = record.outputs.contains { $0.name == MomentOutput.outputName && $0.result.ok }
            checks.append(Check(step: i + 1, line: record.line ?? "", expected: expect, react: react,
                                move: ran ? MomentOutput.move(record.answers) : nil,
                                intensity: ran ? MomentOutput.size(record.answers).name : nil,
                                say: ran ? MomentOutput.saying(record.answers) : nil,
                                said: ran ? lastSaid : nil, saidTakes: ran ? lastTakes : [], sign: ran ? lastSign : nil,
                                mood: moodNow(), offered: timeline.last?.offered ?? [], dropped: record.dropped,
                                latencyMs: record.latencyMs,
                                told: toldDream))
        }
        if let s = since, let end = scenario.steps.last?.atMs { working.append((s, end)) }
        // A scripted brain's answers are the scenario's own: only the checks
        // a run can fail without Jev are its to judge.
        let judged = judgesChoices ? scenario.checks : scenario.checks?.withoutChoices
        let runChecks = judged.map { Eval.judge($0, timeline: timeline, working: working, start: scenario.mood) } ?? []
        return Result(scenario: scenario.name, file: scenario.file, checks: checks, runChecks: runChecks, timeline: timeline)
    }

    /// The whole-run checks (internal/EVALS.md §3) against a run's passes, the
    /// spans its turn worked and the mood it started in.
    static func judge(_ c: Scenario.Checks, timeline: [Pass], working: [(Int64, Int64)],
                      start: String = MoodOutput.initial) -> [RunCheck] {
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
        if let range = c.wordsSaid {
            let said = played.filter { $0.reaction?.said != "none" }.count
            let share = played.isEmpty ? 0 : Double(said) / Double(played.count)
            out.append(RunCheck(name: "words_said \(range.lowerBound)-\(range.upperBound)", passed: range.contains(share),
                                detail: "\(said) of \(played.count) reactions said something"))
        }
        if !c.signsSeen.isEmpty {
            let at = timeline.first { $0.sign.map(c.signsSeen.contains) == true }
            out.append(RunCheck(name: "signs_seen \(c.signsSeen.joined(separator: "|"))", passed: at != nil,
                                detail: at.map { "\($0.sign ?? "") at \(clock($0.atMs))" }
                                    ?? "never: \(timeline.compactMap(\.sign).joined(separator: ", "))"))
        }
        for mood in c.moodsSeen {
            let at = timeline.first { $0.mood == mood }
            out.append(RunCheck(name: "moods_seen \(mood)", passed: at != nil,
                                detail: at.map { "\(mood) from \(clock($0.atMs))" } ?? "never \(mood): \(Set(timeline.map(\.mood)).sorted().joined(separator: ", "))"))
        }
        if c.onGraph {
            // Each pass's answer against what it offered, and each change
            // against the graph, from the mood before it.
            var before = start
            var wrong: String?
            for p in timeline where wrong == nil {
                if p.dropped?.hasPrefix("jev: no usable answer for \(MoodOutput.outputName)") == true {
                    wrong = "at \(clock(p.atMs)): no usable mood answer"
                } else if p.dropped == nil, let answer = p.answer, !p.offered.contains(answer) {
                    wrong = "at \(clock(p.atMs)): answered \(answer), offered \(p.offered.joined(separator: "|"))"
                } else if p.mood != before, !(MoodGraph.neighbours[before]?.all.contains(p.mood) ?? false) {
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
            let did = p.dropped.map { "dropped: \($0)" } ?? p.reaction.map { "\($0.text), \(p.intensity ?? "small")" } ?? "none"
            return "    \(t)  \(p.line)  → \(did)  [\(p.mood)]\(p.brain == ExpectBrain().id ? "  (expect brain)" : "")"
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
        /// What the last pass's reaction said, if any, and its takes'
        /// texts.
        var said: String?
        /// And the narration it carried.
        var narration: String?
        var takes: [String] = []
        var sign: String?
    }

    /// A step as it reaches the pipeline: the hook events or pokes it
    /// stands for, in Claude's session (`s1` unless it says) in `landing`,
    /// each one input. Every hook says which process the agent is, as a
    /// real agent's do: a demo's, one to each session, which runs all
    /// through the scenario.
    public static func inputs(_ step: Scenario.Step, at now: Int64) -> [(Pipeline) -> Pipeline.Step] {
        let cwd = step.workspace.map { "/eval/landing/.worktrees/\($0)" } ?? "/eval/landing"
        let session = step.session ?? "s1"
        let source = step.agent ?? .claude
        func hook(_ type: Event.Kind, _ phase: Event.Phase, _ specific: String,
                  _ data: [String: JSONValue] = [:], subagent: String? = nil) -> (Pipeline) -> Pipeline.Step {
            var data = data
            data["process"] = Eval.agentProcess(session)
            return { $0.agent(Event(at: now, source: source, type: type, phase: phase, specificType: specific, session: session,
                                    subagent: subagent, cwd: cwd, data: data), labels: step.labels) }
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
            // A whole command in one moment is no work act: its start would
            // be a pass of its own. `half` plays one.
            if let topic = step.topic, step.half != nil { start["topic"] = .string(topic) }
            if let program = step.program {
                start["program"] = .string(program)
                end["program"] = .string(program)
                start["tool_use_id"] = "eval-command"
                end["tool_use_id"] = "eval-command"
            }
            let hooks = [hook(.tool, .start, "PreToolUse", start),
                         hook(.tool, .end, step.failed == true && source == .claude ? "PostToolUseFailure" : "PostToolUse", end)]
            return step.half == "start" ? [hooks[0]] : step.half == "end" ? [hooks[1]] : hooks
        // An edit that removes `count` lines and adds none: the counts the
        // hook gives, never the text.
        case "edit":
            let lines: [String: JSONValue] = ["tool": "Edit", "lines_added": 0, "lines_removed": .int(Int64(step.count ?? 100))]
            return [hook(.tool, .start, "PreToolUse", lines), hook(.tool, .end, "PostToolUse", lines.merging(["failed": false]) { a, _ in a })]
        // The agent writes its to-do list: Claude's TodoWrite, its counts
        // as the hook gives them, never the items.
        case "to-do list":
            let list: [String: JSONValue] = ["tool": "TodoWrite", "todos_done": .int(Int64(step.todos?.done ?? 0)),
                                             "todos_total": .int(Int64(step.todos?.total ?? 0))]
            return [hook(.tool, .start, "PreToolUse", list), hook(.tool, .end, "PostToolUse", ["tool": "TodoWrite", "failed": false])]
        case "poke": return [{ $0.poke(at: now) }]
        case "hush": return [{ $0.effects($0.core.hush(forMs: Core.hushMs, by: .app, at: now), at: now) }]
        case "pokes": return (0..<(step.count ?? 4)).map { _ in { $0.poke(at: now) } }
        // A Claude session opens with no turn yet: Boop is awake and idle,
        // not asleep. No line, so no pass.
        case "session started": return [hook(.session, .start, "SessionStart", ["source": "startup"])]
        // The agent's context compacted, mid-turn: a session start that
        // says so.
        case "compact": return [hook(.session, .start, source == .codex ? "PostCompact" : "SessionStart", ["source": "compact"])]
        // Claude asks to run a command, and later you answer it: the
        // request's wait, then its call's result.
        case "needs you": return [hook(.tool, .start, "PreToolUse", ["tool": "Bash"]), hook(.tool, .wait, "PermissionRequest", ["tool": "Bash"])]
        case "answered": return [hook(.tool, .end, "PostToolUse", ["tool": "Bash", "failed": false])]
        case "said": return [{ $0.said(step.words ?? "", by: .device, at: now) }]
        // BOOT pressed: it hands you the next agent, or pokes.
        case "press": return [{ $0.press(at: now) }]
        // The agent sends a helper off, and it comes back.
        case "helper started": return [hook(.subagent, .start, "SubagentStart", subagent: step.helper ?? "h1")]
        case "helper returned": return [hook(.subagent, .end, "SubagentStop", subagent: step.helper ?? "h1")]
        // What you did to the board, which reacted to it at once: a hold
        // names the request the needs-you screen shows, as the board does.
        case "wish":
            // A wish made, as the brain's pick of its sign makes it.
            let kind = Core.WishKind(rawValue: step.kind ?? "") ?? .pet
            return [{ $0.effects($0.core.makeWish(kind, at: now), at: now) }]
        case "gesture":
            return [{ $0.gesture(step.kind ?? "stroke", request: $0.core.snapshot(at: now).attn?.id, at: now) }]
        // What the presence detector would decide: you
        // lock the screen and leave now, and later unlock it.
        case "away": return [{ $0.presence(Event(at: now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                                 data: ["since": .int(now)])) }]
        case "back": return [{ $0.presence(Event(at: now, source: .mac, type: .presence, phase: .end, specificType: "unlocked")) }]
        // The screen locks and unlocks, as the detector says so at once:
        // an `unlock` is since the last `lock`.
        case "lock": return [{ $0.lock(PresenceDetector.lockEvent(at: now)) }]
        case "unlock": return [{ p in
            let since = p.transcript.events.last { $0.kind == Event.kind(.lock, .start) }?.at ?? now
            return p.lock(PresenceDetector.unlockEvent(since: since, at: now))
        }]
        // The board ends the last ask: the left answer tapped, the right,
        // a touch, or nobody.
        case "ask answered": return [{ $0.answerLast(step.pick ?? "a", at: now) ?? $0.tick(at: now) }]
        default: return []  // wait
        }
    }

    /// The agent's process on every hook of the session `session`, as a
    /// demo's agent has it: one to each session.
    static func agentProcess(_ session: String) -> JSONValue {
        let process = DemoPlayer.agentProcess(for: session)
        return .object(["pid": .int(Int64(process.pid)), "started": .int(process.started)])
    }

    /// One scenario's runs, readably: its verdict, and each failing step
    /// once.
    public static func report(_ runs: [Result], story: String? = nil, gap: String? = nil, judged: Bool = false) -> [String] {
        guard let first = runs.first else { return [] }
        let passed = runs.filter(\.passed).count
        let tally = runs.count > 1 ? "  (\(passed)/\(runs.count) runs)" : ""
        let verdict = passed == runs.count ? (judged ? "judge " : gap == nil ? "pass  " : "pass  (gap closed: take out its gap) ") : gap == nil ? "FAIL  " : "GAP   "
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
