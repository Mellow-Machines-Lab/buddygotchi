import AgentHooks
import BoopDevKit
import BoopKit
import Foundation
import MellowHarness

// Developer CLI (VERIFICATION.md §2): eval, check and hooks,
// as `usage` describes.

/// Each subcommand's usage, in the order `boopdev --help` lists them.
let usages: [(command: String, text: String)] = [
    ("eval", """
    boopdev eval [--level quick|standard|full] [--runs N] [--only TEXT] [--always] [--labeler apple] [--timeline] [--scenarios DIR] [--steering DIR]
    boopdev eval --list [--level quick|standard|full] [--runs N] [--always] [--only TEXT] [--scenarios DIR] [--steering DIR]
    boopdev eval --scripted [--only TEXT] [--always] [--timeline] [--scenarios DIR] [--steering DIR]
        Runs the harness eval scenarios (internal/EVALS.md): hook-level steps on a virtual clock through a fresh
        pipeline, the real harness and outputs, and Jev, each pass checked against what it should come to (the
        reaction, what it says, how long the face holds and the mood), and each run against its whole-run
        checks. Needs Jev's key in BOOP_JEV_KEY and fails without it. --level says how much asks Jev: quick (the
        default) the must scenarios, Jev answering only the passes of steps that expect one and the expect
        brain the rest unless whole-run checks read them all, and --only also runs a named feel scenario, in
        full; standard is every scenario once, every pass to Jev; full is that with always scenarios 3 times,
        only when the owner asks (make eval). A must's failed run gets one re-run. A feel scenario has no exact
        checks on Jev: its trajectory goes beside the run's file, for the judge (EVALS.md §2). --runs runs each scenario N times (default
        the scenario's own runs, else 1, or 3 for an always scenario at full); it passes only if every run does.
        Before asking Jev anything it counts the requests (each run's passes with the expect brain), and refuses
        the run if that's more than what's left of the day's limit across every command and worktree, kept in
        ~/.boopdev/jev-requests.json. A run that reaches the limit stops and reports what finished.
        BOOP_JEV_OVER_LIMIT=1 goes past the limit, only when the owner says so. --labeler apple reads each prompt and last message with Apple Intelligence on
        this Mac, in place of the step's own reading, so a run checks the reading too. --always runs only
        the always scenarios, Boop's character. --timeline
        prints every pass of every run. --list prints each scenario at the level with its case, runs and
        requests, all three levels' totals and today's count, and runs nothing. --scripted runs each scenario once with the expect brain, which answers every pass as the
        scenario expects, with no key and no Jev requests: what it checks is everything but Jev (that each step
        wakes the brain as it should, the screen, the whole-run checks it can meet). A scripted scenario,
        one that checks only the code's rules, runs only so. A scenario with a known
        gap is reported GAP when it fails, and doesn't fail the eval. Every event, view event and pass goes to the run's own file in
        /tmp/boop-eval, one JSON object a line. Exits 1 if any fails. The scenarios and steering
        default to the pack in use's (characters/CHARACTER.md §2): its evals/ and steering/.
    """),
    ("prompts", """
    boopdev prompts [--only TEXT] [--scenarios DIR] [--steering DIR] [--out FILE]
        What the brain reads in every eval scenario, for the Character Studio's Brain view
        (characters/studio/README.md): each scenario run once with the expect brain, as eval --scripted runs
        it, with no key, and each pass's step, line, prompt, questions and answers, written to FILE
        (default characters/studio/prompts.js in the repo) for the page to load. The scenarios and
        steering default to the pack in use's. A prompt's head, the guide,
        PERSONALITY and MOOD, is kept once for every pass that shares it, and so is each question.
    """),
    ("check", """
    boopdev check [PACK…]
        Checks character packs as the engine reads them (characters/CHARACTER.md): character.json, the
        steering, the faces' files, the voice and every demo script, then its moods, what it uses and the
        studio (characters/charactergen.py --check). PACK is a pack's folder; without one, every pack in
        the repo's characters/. Prints each problem, which stops a pack from working, and each note,
        which doesn't. Exits 1 on a problem.
    """),
    ("read-check", """
    boopdev read-check [--fixture FILE] [--min-kind SHARE] [--min-tone SHARE] [--min-phrases SHARE] [--max-ms MS] [--verbose]
        Reads sample prompts and agents' last messages with Apple Intelligence on this Mac, as the app does,
        and scores each against what it expects: its kind, its tone, one of its phrases picked, and a secret
        planted in it never coming back, prompts and messages apart. Exits 1 if a secret comes back, a score
        of either is under its floor (--min-kind and --min-tone 0.85,
        --min-phrases 0.75 by default) or a typical reading takes longer than --max-ms (1500). FILE defaults
        to the repo's internal/app/Tests/Fixtures/readings.json. It prints each miss, or with
        --verbose every reading. Needs Apple Intelligence; exits 1 without it.
    """),
    ("memory", """
    boopdev memory write [--fixture FILE] [--only TEXT]
        Runs the dream's write with Apple Intelligence on this Mac, as the app does, over fixture nights
        (each a memory, CERTAIN, its RECENT lines and what a person would accept), and prints each night's reply,
        the edits applied, the refusals and the memory after it, for a person to judge the prompt by. FILE
        defaults to the repo's internal/app/Tests/Fixtures/memory-nights.json. Needs Apple Intelligence; exits 1
        without it.
    boopdev memory gates
        Scores each small yes-or-no question the write asks against labeled sentences (memory-gates.json). Needs
        Apple Intelligence.
    """),
    ("hooks", """
    boopdev hooks status|install|remove [claude|codex] --home DIR [--hook PATH]
        Boop's installer, against any HOME (tests use a temporary one). --hook defaults to the agent-hook
        next to boopdev.
    """),
]

let version = "(boop \(BoopVersion.current))"
/// Indented under "usage:", as each command's own lines are under it.
func indented(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
}
let usage = "usage:\n" + usages.map { indented($0.text) }.joined(separator: "\n") + "\n"
    + "Each command prints its own usage with --help, and stops on a flag it doesn't take.\n" + version

/// The `agent-hook` built next to boopdev.
let builtHook = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent(HookInstaller.client)

/// A subcommand's arguments, checked against what it takes (VERIFICATION.md
/// §2): --help prints its usage and exits, and anything else stops it.
func arguments(_ command: String, _ args: [String], options: Set<String> = [], flags: Set<String> = [],
               words: Int = 0) -> Arguments {
    let text = "usage:\n" + indented(usages.first { $0.command == command }?.text ?? "") + "\n" + version
    return Arguments.parse(args, options: options, flags: flags, words: words, command: "boopdev \(command)", usage: text)
}

/// The Boop repo: the nearest folder with `characters/charactergen.py` above
/// the working directory, or else above boopdev itself (`.build/debug`).
func findRepo() -> URL? {
    let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                  URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()]
    for start in starts {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("characters/charactergen.py").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
    }
    return nil
}

func eval(_ raw: [String]) async {
    let args = arguments("eval", raw, options: ["--level", "--runs", "--only", "--scenarios", "--steering", "--labeler"],
                         flags: ["--always", "--list", "--timeline", "--scripted"])
    // The pack in use's scenarios and steering (characters/CHARACTER.md §2), unless given.
    func path(_ option: String, _ inPack: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        return CharacterPack.active.directory.appendingPathComponent(inPack)
    }
    var list: [Scenario]
    let scenarios = path("--scenarios", "evals")
    do { list = try Scenario.load(directory: scenarios) } catch { fail("can't read the scenarios: \(error)") }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    if args.has("--always") { list = list.filter(\.always) }
    guard let level = Eval.Level(rawValue: args["--level"] ?? "quick") else {
        fail("boopdev eval: --level is quick, standard or full, not \(args["--level"] ?? "")")
    }
    let named = args["--only"] != nil
    guard !list.isEmpty else { fail("no scenarios in \(scenarios.path)") }
    // A scripted scenario checks the code's rules: only the expect brain runs it.
    let scripted = args.has("--scripted")
    if !scripted {
        let forJev = list.filter { !$0.scripted }
        guard !forJev.isEmpty else { fail("\(list.map(\.file).joined(separator: ", ")): scripted, so run with --scripted") }
        if forJev.count < list.count, !args.has("--list") { print("\(list.count - forJev.count) scripted scenario\(list.count - forJev.count == 1 ? "" : "s") left out: --scripted runs them") }
        if !args.has("--list") { list = forJev }
    }
    let steering: Steering
    do { steering = try Steering(directory: path("--steering", "steering")) } catch { fail("\(error)") }
    let given = args["--runs"].map { Int($0) }
    if let given, (given ?? 0) < 1 { fail("--runs is a count, 1 or more") }
    func planOf(_ s: Scenario, _ level: Eval.Level) -> Eval.Plan? {
        Eval.plan(s, level: level, named: named, given: given.flatMap { $0 })
    }
    let listing = args.has("--list")
    // What the eval will cost before it asks Jev anything (EVALS.md §2):
    // each scenario's passes with the expect brain, times its runs. Only
    // what's used: nothing for --scripted, all for --list, else the level's.
    var priced: [(scenario: Scenario, price: Eval.Price)] = []
    for scenario in list where !scripted && (listing || planOf(scenario, level) != nil) {
        do { priced.append((scenario, try await Eval.price(scenario, steering: steering))) } catch { fail("\(error)") }
    }
    func requests(_ price: Eval.Price, _ plan: Eval.Plan) -> Int { plan.scriptsSetup ? price.expected : price.all }
    func total(_ level: Eval.Level) -> (scenarios: Int, requests: Int) {
        let those = priced.compactMap { p in planOf(p.scenario, level).map { (p.price, $0) } }
        return (those.count, those.reduce(0) { $0 + $1.1.runs * requests($1.0, $1.1) })
    }
    let allowance = JevAllowance(overridden: JevAllowance.overriddenByEnvironment())
    if listing {
        for p in priced where p.scenario.scripted || planOf(p.scenario, level) != nil {
            let s = p.scenario
            print("\(s.file)\(s.always ? "  [always]" : s.scripted ? "  [scripted]" : s.gap != nil ? "  [gap]" : "")\(s.talk == .default ? "" : "  [\(s.talk.rawValue)]")  \(s.name)")
            if let plan = planOf(s, level) {
                print("    \(plan.runs) run\(plan.runs == 1 ? "" : "s") × about \(requests(p.price, plan)) requests")
            } else {
                print("    expect brain only, no Jev requests")
            }
            print("    \(s.story)")
            if let gap = s.gap { print("    gap: \(gap)") }
        }
        for l in Eval.Level.allCases {
            let t = total(l)
            print("\(l == level ? "▸" : " ") \(l.rawValue): \(t.scenarios) scenario\(t.scenarios == 1 ? "" : "s"), about \(t.requests) Jev requests")
        }
        do {
            let used = try allowance.used()
            print("today: \(used) of \(allowance.limit) used, in \(allowance.file.path)")
        } catch { print("today: \(error)") }
        exit(0)
    }
    var plan: [(scenario: Scenario, plan: Eval.Plan)]
    let estimate: Int
    if scripted {
        plan = list.map { ($0, Eval.Plan.scripted) }
        estimate = 0
    } else {
        plan = priced.compactMap { p in planOf(p.scenario, level).map { (p.scenario, $0) } }
        guard !plan.isEmpty else { fail("boopdev eval: nothing to run at the \(level.rawValue) level") }
        let left = list.count - plan.count
        if left > 0 { print("\(left) scenario\(left == 1 ? "" : "s") with whole-run checks left out: --level standard runs them") }
        estimate = total(level).requests
        do {
            if let refusal = try allowance.refusal(estimate: estimate, wholeFullRun: level == .full && !named) { fail("boopdev eval: \(refusal)") }
        } catch { fail("boopdev eval: can't read today's count: \(error)") }
    }
    let brain: any Brain
    var counted: CountedBrain?
    if scripted {
        brain = ExpectBrain()
    } else {
        guard let key = JevKey.environment() else {
            fail("boopdev eval asks Jev, and needs its API key in \(JevKey.variable)")
        }
        counted = CountedBrain(JevBrain(key: key), allowance: allowance)
        brain = counted!
        if allowance.overridden { print("\(JevAllowance.overrideVariable) is set: this run may pass today's limit of \(allowance.limit)") }
    }
    var runner = Eval(brain: brain, steering: steering)
    switch args["--labeler"] {
    case nil: break
    case "apple":
        guard let labeler = AppleIntelligenceLabeler.ifAvailable() else { fail("boopdev eval: Apple Intelligence isn't available on this Mac") }
        runner.labeler = labeler
    case let other?: fail("boopdev eval: --labeler is apple, not \(other)")
    }
    let log = evalDebugLog()
    DebugLog.start(log)
    runner.debugLog = log
    print(scripted ? "\(plan.count) scenario\(plan.count == 1 ? "" : "s") with the expect brain"
        : "\(level.rawValue): \(plan.count) scenario\(plan.count == 1 ? "" : "s"), about \(estimate) Jev requests")
    print("every event, view event and pass goes to \(log.path)")
    var results: [[Eval.Result]] = []
    var gapsFailed = 0
    var failed = false
    var stopped: String?
    let trajectories = log.deletingPathExtension().appendingPathExtension("trajectories.jsonl")
    var judged = 0
    // One run. Nil when the limit cut it short, which says nothing about Jev.
    func play(_ scenario: Scenario) async -> Eval.Result? {
        do {
            let result = try await runner.run(scenario)
            if let why = counted?.stopped {
                stopped = why
                return nil
            }
            if !scripted { LineFile.append(JSONLine.encode(Eval.trajectory(result, scenario: scenario)), to: trajectories) }
            return result
        } catch {
            if let why = counted?.stopped {
                stopped = why
                return nil
            }
            fail("\(error)")
        }
    }
    scenarios: for (scenario, plan) in plan {
        var rs: [Eval.Result] = []
        runner.scriptsSetup = plan.scriptsSetup
        for _ in 1...plan.runs {
            guard let result = await play(scenario) else { break scenarios }
            rs.append(result)
        }
        // A must's failure gets its one re-run, to confirm before it blocks.
        if plan.rerunsOnFailure, rs.contains(where: { !$0.passed }) {
            for line in Eval.report(rs, story: scenario.story) { print(line) }
            guard let again = await play(scenario) else { break scenarios }
            print("  re-run: \(again.passed ? "passed, so it doesn't block" : "failed again")")
            rs = [again]
        }
        results.append(rs)
        if scenario.brief != nil, !scripted { judged += 1 }
        if !rs.allSatisfy(\.passed) {
            if scenario.gap != nil { gapsFailed += 1 } else { failed = true }
        }
        for line in Eval.report(rs, story: scenario.story, gap: scenario.gap, judged: scenario.brief != nil && !scripted) { print(line) }
        if args.has("--timeline") {
            for (i, r) in rs.enumerated() {
                print("  run \(i + 1)\(r.passed ? "" : " (failed)"):")
                for line in Eval.timeline(r) { print(line) }
            }
        }
    }
    print(Eval.summary(results, gaps: gapsFailed) + " in every run with \(brain.id)")
    let latencies = results.flatMap { $0.flatMap { $0.checks.map(\.latencyMs) } }.sorted()
    if !latencies.isEmpty {
        print("latency: median \(latencies[latencies.count / 2]) ms, slowest \(latencies.last!) ms (deadline \(Harness.Options().deadlineMs) ms)")
    }
    if let counted {
        let today = (try? allowance.used()).map { "; today \($0) of \(allowance.limit)" } ?? ""
        print("requests: \(counted.requests) to Jev, about \(estimate) expected\(today)")
    }
    if judged > 0 { print("feel: \(judged) for the judge; each run's trajectory: \(trajectories.path)") }
    if let stopped { print("stopped: \(stopped); \(results.count) of \(plan.count) scenarios finished, the rest didn't run") }
    print("every event and pass, with its state: \(log.path)")
    exit(failed || stopped != nil ? 1 : 0)
}

func prompts(_ raw: [String]) async {
    let args = arguments("prompts", raw, options: ["--only", "--scenarios", "--steering", "--out"])
    let repo = findRepo()
    // The pack in use's scenarios and steering (characters/CHARACTER.md §2), unless given.
    func path(_ option: String, _ inPack: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        return CharacterPack.active.directory.appendingPathComponent(inPack)
    }
    var list: [Scenario]
    do { list = try Scenario.load(directory: path("--scenarios", "evals")) } catch { fail("can't read the scenarios: \(error)") }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    let steeringDir = path("--steering", "steering")
    let steering: Steering
    do { steering = try Steering(directory: steeringDir) } catch { fail("\(error)") }
    // Heads and questions once each, by their index; a pass names them.
    var heads: [String] = [], questions: [[String: Any]] = []
    var headIndex: [String: Int] = [:], questionIndex: [String: Int] = [:]
    func index(_ q: Question) -> Int {
        let options = q.options.map { ["name": $0.name, "what": $0.what, "not_for": $0.notFor ?? NSNull()] as [String: Any] }
        let value: [String: Any] = ["key": q.key, "text": q.text, "about": q.about, "judge_by": q.judgeBy, "options": options]
        let id = JSONLine.encode(value)
        if let i = questionIndex[id] { return i }
        questions.append(value)
        questionIndex[id] = questions.count - 1
        return questions.count - 1
    }
    var scenarios: [String: [[String: Any]]] = [:]
    for scenario in list {
        var passes: [[String: Any]] = []
        var runner = Eval(brain: ExpectBrain(), steering: steering)
        runner.onPass = { step, p in
            var pass: [String: Any] = ["step": step, "line": p.line ?? "",
                                       "answers": p.answers.mapValues(\.choice)]
            if let held = p.held { pass["held"] = held }
            if let dropped = p.dropped { pass["dropped"] = dropped }
            if let prompt = p.prompt {
                let (head, rest) = DebugLog.split(prompt)
                if headIndex[head] == nil {
                    heads.append(head)
                    headIndex[head] = heads.count - 1
                }
                pass["head"] = headIndex[head]
                pass["rest"] = rest
                pass["questions"] = p.questions.map(index)
            }
            passes.append(pass)
        }
        do { _ = try await runner.run(scenario) } catch { fail("\(error)") }
        scenarios[(scenario.file as NSString).deletingPathExtension] = passes
    }
    let folder = steeringDir.standardizedFileURL.deletingLastPathComponent()
    let pack = (try? CharacterPack(directory: folder))?.id ?? folder.lastPathComponent
    let data = JSONLine.encode(["pack": pack, "heads": heads, "questions": questions, "scenarios": scenarios] as [String: Any])
    guard let out = args["--out"].map({ URL(fileURLWithPath: $0) }) ?? repo?.appendingPathComponent("characters/studio/prompts.js") else {
        fail("boopdev prompts: can't find the Boop repo; run it inside the repo, or pass --out")
    }
    do {
        try ("// Generated by boopdev prompts. Do not edit.\nwindow.StudioPrompts = \(data);\n").write(to: out, atomically: true, encoding: .utf8)
    } catch { fail("can't write \(out.path): \(error)") }
    let count = scenarios.values.reduce(0) { $0 + $1.count }
    print("\(out.path): \(count) passes in \(scenarios.count) scenarios, \(heads.count) heads, \(questions.count) questions")
}

/// A file of the run's own, so runs side by side
/// don't write over each other. Runs over a day old are cleared away.
func evalDebugLog() -> URL {
    let dir = URL(fileURLWithPath: "/tmp/boop-eval")
    let fm = FileManager.default
    let dayAgo = Date().addingTimeInterval(-86_400)
    for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    where (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).flatMap { $0 < dayAgo } == true {
        try? fm.removeItem(at: file)
    }
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    return dir.appendingPathComponent("\(stamp.string(from: Date()))-\(getpid()).jsonl")
}

func hooks(_ raw: [String]) {
    let args = arguments("hooks", raw, options: ["--home", "--hook"], words: 2)
    guard let action = args.words.first, ["status", "install", "remove"].contains(action) else {
        fail("boopdev hooks: status, install or remove?")
    }
    // Never the real HOME by default: tests use a temporary one.
    guard let home = args["--home"] else { fail("boopdev hooks: pass --home DIR") }
    let installer = HookInstaller.boop(home: URL(fileURLWithPath: home), hookPath: args["--hook"] ?? builtHook.path)
    var agents = Agent.allCases
    if args.words.count > 1 {
        guard let agent = Agent(rawValue: args.words[1]) else { fail("boopdev hooks: the agent is claude or codex") }
        agents = [agent]
    }
    for agent in agents {
        do {
            switch action {
            case "install": try installer.install(agent)
            case "remove": try installer.remove(agent)
            default: break
            }
        } catch {
            fail("\(agent.rawValue): \(error.localizedDescription)")
        }
        print("\(agent.rawValue): \(installer.health(agent))")
    }
}

func check(_ raw: [String]) {
    let args = arguments("check", raw, words: Int.max)
    // The repo: the nearest folder with characters/charactergen.py above here, or above boopdev.
    let repo = [FileManager.default.currentDirectoryPath, CommandLine.arguments[0]].lazy.compactMap { start -> URL? in
        var dir = URL(fileURLWithPath: start).resolvingSymlinksInPath().standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("characters/charactergen.py").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }.first
    var packs = args.words.map { URL(fileURLWithPath: $0).standardizedFileURL }
    if packs.isEmpty {
        guard let repo else { fail("boopdev check: no repo here; name a pack's folder") }
        let folder = repo.appendingPathComponent("characters")
        packs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("character.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var failed = false
    for pack in packs {
        let found = PackCheck(pack)
        failed = failed || !found.problems.isEmpty
        print("\(pack.lastPathComponent): " + (found.problems.isEmpty ? "ok" : "\(found.problems.count) problem\(found.problems.count == 1 ? "" : "s")"))
        for p in found.problems { print("  problem: \(p)") }
        for n in found.notes { print("  note: \(n)") }
    }
    // The moods, what the pack uses and the studio, as charactergen.py checks them.
    fflush(stdout)
    if let repo {
        for each in args.words.isEmpty ? [nil] : packs.map(Optional.some) {
            let python = Process()
            python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            python.arguments = [repo.appendingPathComponent("characters/charactergen.py").path, "--check"] + (each.map { [$0.path] } ?? [])
            do { try python.run() } catch { fail("boopdev check: can't run charactergen.py: \(error)") }
            python.waitUntilExit()
            failed = failed || python.terminationStatus != 0
        }
    }
    exit(failed ? 1 : 0)
}

func readCheck(_ raw: [String]) async {
    let args = arguments("read-check", raw, options: ["--fixture", "--min-kind", "--min-tone", "--min-phrases", "--max-ms"],
                         flags: ["--verbose"])
    let file = args["--fixture"].map { URL(fileURLWithPath: $0) }
        ?? findRepo()?.appendingPathComponent("internal/app/Tests/Fixtures/readings.json")
    let samples: [ReadCheck.Sample]
    do {
        guard let file else { fail("boopdev read-check: can't find the fixture; pass --fixture FILE") }
        samples = try ReadCheck.samples(Data(contentsOf: file))
    } catch {
        fail("boopdev read-check: \(error)")
    }
    var floors = ReadCheck.Floors()
    for (option, keyPath) in [("--min-kind", \ReadCheck.Floors.kind), ("--min-tone", \.tone), ("--min-phrases", \.phrases)] {
        guard let v = args[option] else { continue }
        guard let share = Double(v) else { fail("boopdev read-check: \(option) is a share, like 0.85") }
        floors[keyPath: keyPath] = share
    }
    if let v = args["--max-ms"] {
        guard let ms = Int(v) else { fail("boopdev read-check: --max-ms is a number of ms") }
        floors.medianMs = ms
    }
    guard let labeler = AppleIntelligenceLabeler.ifAvailable() else { fail("boopdev read-check: Apple Intelligence isn't available on this Mac") }
    let results = await ReadCheck.run(samples, labeler: labeler)
    for r in results where args.has("--verbose") || r.kindOK == false || r.toneOK == false || r.phrasesOK == false || r.leaked {
        func field(_ got: String?, _ want: String?, _ ok: Bool?) -> String {
            (got ?? "none") + (ok == false ? " (not \(want ?? "none"))" : "")
        }
        let line = [field(r.kind, r.sample.kind, r.kindOK), field(r.tone, r.sample.tone, r.toneOK),
                    "\(r.phrases)" + (r.phrasesOK == false ? " (not one of \(r.sample.phrases ?? []))" : ""), r.leaked ? "LEAKED" : nil]
        let flat = r.sample.raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        let ok = r.kindOK != false && r.toneOK != false && r.phrasesOK != false && !r.leaked
        print("\(ok ? "ok  " : "MISS")  \(r.ms) ms  \(r.sample.isMessage ? "message" : "prompt ")  \(line.compactMap { $0 }.joined(separator: ", "))  \"\(flat.prefix(50))\"")
    }
    // Prompts and messages are scored apart: each has its own lists.
    var short: [String] = []
    for (name, group) in [("prompts", results.filter { !$0.sample.isMessage }), ("messages", results.filter(\.sample.isMessage))] where !group.isEmpty {
        let score = ReadCheck.score(group)
        let secrets = group.filter { $0.sample.secret != nil }.count
        print("\(name): kind \(score.kind.hits)/\(score.kind.of), tone \(score.tone.hits)/\(score.tone.of), phrases \(score.phrases.hits)/\(score.phrases.of), "
              + "secrets kept out \(secrets - score.leaks.count)/\(secrets), median \(score.medianMs) ms")
        short += score.shortfalls(floors).map { "\(name)' \($0)" }
    }
    guard short.isEmpty else { fail("boopdev read-check: " + short.joined(separator: "; ")) }
}

/// `boopdev memory write`: the dream's write over fixture nights.
func memory(_ raw: [String]) async {
    if raw.first == "gates" {
        guard #available(macOS 26.0, *), AppleIntelligenceLabeler.isAvailable else { fail("boopdev memory gates: Apple Intelligence isn't available on this Mac") }
        guard let file = findRepo()?.appendingPathComponent("internal/app/Tests/Fixtures/memory-gates.json") else { fail("boopdev memory gates: no repo here") }
        await memoryGates(file)
        return
    }
    guard raw.first == "write" else { fail("boopdev memory: the command is write or gates\n\(usage)") }
    let args = arguments("memory", Array(raw.dropFirst()), options: ["--fixture", "--only"], flags: [])
    guard let file = args["--fixture"].map({ URL(fileURLWithPath: $0) })
            ?? findRepo()?.appendingPathComponent("internal/app/Tests/Fixtures/memory-nights.json"),
          let data = try? Data(contentsOf: file),
          let nights = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
        fail("boopdev memory write: can't read the fixture; pass --fixture FILE")
    }
    guard AppleIntelligenceLabeler.isAvailable else {
        fail("boopdev memory write: Apple Intelligence isn't available on this Mac")
    }
    let writer = MemoryPipelineWriter()
    for night in nights {
        let name = night["name"] as? String ?? "?"
        if let only = args["--only"], !name.localizedCaseInsensitiveContains(only) { continue }
        guard let day = night["day"] as? String, let certain = night["certain"] as? String,
              let memory = WrittenMemory.from(notes: night["memory"] as? [String] ?? []) else {
            fail("boopdev memory write: \(name) doesn't read")
        }
        let journal = (night["yesterday"] as? [String] ?? []).map { line in
            (at: String(line.prefix(5)), line: String(line.dropFirst(6)))
        }
        // One night, so no habit: what you said and the day line.
        let weekday = LocalTime().weekday(of: day)
        let tonight = DayDigest.from(day: day, weekday: weekday, tallies: .init(), first: "", last: "", journal: journal)
        let input = MemoryPipeline.Input(memory: memory, digests: [tonight], certain: certain, journal: journal, day: day, weekday: weekday)
        let request = MemoryRequest(input)
        let started = Date()
        let reply = await writer.write(request)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("== \(name)  (\(ms) ms)")
        print("   accept: \(night["accept"] as? String ?? "")")
        guard case .reply(let text) = reply else { print("   no reply: \(reply)"); continue }
        print("   reply:\n" + text.split(separator: "\n").map { "     " + $0 }.joined(separator: "\n"))
        let (after, report) = MemoryEdits.apply(text, to: memory, numbered: request.numbered, day: day,
                                                words: MemoryRequest.words(in: journal),
                                                source: input.source)
        print("   updated \(report.updated), added \(report.added), dropped \(report.dropped), kept \(report.kept), aged \(report.aged)")
        for r in report.refused { print("   REFUSED \(r.why): \(r.line)") }
        print("   after:\n" + after.markdown.split(separator: "\n").filter { $0.hasPrefix("- ") }.map { "     " + $0 }.joined(separator: "\n"))
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "memory":
    await memory(Array(args.dropFirst()))
case "eval":
    await eval(Array(args.dropFirst()))
case "prompts":
    await prompts(Array(args.dropFirst()))
case "check":
    check(Array(args.dropFirst()))
case "hooks":
    hooks(Array(args.dropFirst()))
case "read-check":
    await readCheck(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
case let command?:
    fail("boopdev: no command \(command)\n\(usage)")
}
