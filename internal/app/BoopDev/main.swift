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
    boopdev eval [--runs N] [--only TEXT] [--always] [--budget N | --no-budget] [--labeler apple] [--timeline] [--scenarios DIR] [--steering DIR]
    boopdev eval --list [--always] [--only TEXT] [--scenarios DIR] [--steering DIR]
    boopdev eval --scripted [--only TEXT] [--always] [--timeline] [--scenarios DIR] [--steering DIR]
    boopdev eval --to-demo DIR [--only TEXT] [--always] [--scenarios DIR]
        Runs the harness eval scenarios (internal/EVALS.md): hook-level steps on a virtual clock through a fresh
        pipeline, the real harness and outputs, and Jev, each pass checked against what it should come to (the
        reaction, what it says, how long the face holds and the mood), and each run against its whole-run
        checks. Needs Jev's key in BOOP_JEV_KEY and fails without it. --runs runs each scenario N times
        (default the scenario's own runs, else 3 for an always scenario and 1 for the rest); it passes only
        if every run does. Before asking Jev anything it counts the requests the runs will send (each run's
        passes with the scripted brain) and stops if that's over --budget (default 100); --no-budget is for
        the final pass (make eval). --labeler apple reads each prompt and last message with Apple Intelligence on
        this Mac, in place of the step's own reading, so a run checks the reading too. --always runs only
        the always scenarios, Boop's character. --timeline
        prints every pass of every run. --list prints each scenario's case, runs and requests, and runs
        nothing. --scripted runs each scenario once with the expect brain, which answers every pass as the
        scenario expects, with no key and no budget: what it checks is everything but Jev (that each step
        wakes the brain as it should, the screen, the whole-run checks it can meet). --to-demo writes each
        scenario as a demo script, DIR/<scenario>.jsonl, the expect brain's answers as its brain steps, for
        make demo to play (characters/DEMOS.md). A scenario with a known gap is reported GAP when it
        fails, and doesn't fail the eval. Every event, view event and pass goes to the run's own file in
        /tmp/boop-eval, one JSON object a line. Exits 1 if any fails. The scenarios and steering
        default to the Boop repo's, found from the working directory or from boopdev's own place.
    """),
    ("prompts", """
    boopdev prompts [--only TEXT] [--scenarios DIR] [--steering DIR] [--out FILE]
        What the brain reads in every eval scenario, for the Character Studio's Brain view
        (characters/studio/README.md): each scenario run once with the expect brain, as eval --scripted runs
        it, with no key, and each pass's step, line, prompt, questions and answers, written to FILE
        (default characters/studio/prompts.js in the repo) for the page to load. A prompt's head, the guide,
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

/// The Boop repo: the nearest folder with `characters/boop/steering/guide.md` above
/// the working directory, or else above boopdev itself (`.build/debug`).
func findRepo() -> URL? {
    let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                  URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()]
    for start in starts {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("characters/boop/steering/guide.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
    }
    return nil
}

/// How many Jev requests `boopdev eval` may send unless `--budget` or
/// `--no-budget` says (internal/EVALS.md §2): enough for a handful of
/// scenarios while developing, not the whole eval, which is the final pass.
let evalBudget = 100

func eval(_ raw: [String]) async {
    let args = arguments("eval", raw, options: ["--runs", "--only", "--budget", "--scenarios", "--steering", "--to-demo", "--labeler"],
                         flags: ["--always", "--list", "--timeline", "--no-budget", "--scripted"])
    let repo = findRepo()
    func path(_ option: String, _ inRepo: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        guard let repo else { fail("boopdev eval: can't find the Boop repo; run it inside the repo, or pass --scenarios and --steering") }
        return repo.appendingPathComponent(inRepo)
    }
    var list: [Scenario]
    let scenarios = path("--scenarios", "characters/boop/evals")
    do { list = try Scenario.load(directory: scenarios) } catch { fail("can't read the scenarios: \(error)") }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    if args.has("--always") { list = list.filter(\.always) }
    guard !list.isEmpty else { fail("no scenarios in \(scenarios.path)") }
    let steering: Steering
    do { steering = try Steering(directory: path("--steering", "characters/boop/steering")) } catch { fail("\(error)") }
    if let dir = args["--to-demo"] {
        let out = URL(fileURLWithPath: dir)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            for s in list {
                let file = out.appendingPathComponent((s.file as NSString).deletingPathExtension + ".jsonl")
                try DemoFromScenario.script(s, signs: steering.signs).write(to: file, atomically: true, encoding: .utf8)
                print(file.path)
            }
        } catch { fail("can't write the demos: \(error)") }
        exit(0)
    }
    let given = args["--runs"].map { Int($0) }
    if let given, (given ?? 0) < 1 { fail("--runs is a count, 1 or more") }
    let budget = args["--budget"].map { Int($0) }
    if let budget, (budget ?? 0) < 1 { fail("--budget is a count of Jev requests, 1 or more") }
    if budget != nil, args.has("--no-budget") { fail("--budget or --no-budget, not both") }
    // What the eval will cost before it asks Jev anything (EVALS.md §2):
    // each scenario's passes with the scripted brain, times its runs.
    var plan: [(scenario: Scenario, runs: Int, requests: Int)] = []
    for scenario in list {
        let requests: Int
        do { requests = try await Eval.requests(scenario, steering: steering) } catch { fail("\(error)") }
        plan.append((scenario, given.flatMap { $0 } ?? Eval.runs(scenario), requests))
    }
    let total = plan.reduce(0) { $0 + $1.runs * $1.requests }
    if args.has("--list") {
        for p in plan {
            let s = p.scenario
            print("\(s.file)\(s.always ? "  [always]" : s.gap != nil ? "  [gap]" : "")\(s.nature == Scenario.defaultNature ? "" : "  [\(s.nature.rawValue)]")  \(s.name)")
            print("    \(p.runs) run\(p.runs == 1 ? "" : "s") × about \(p.requests) requests")
            print("    \(s.story)")
            if let gap = s.gap { print("    gap: \(gap)") }
        }
        print("\(plan.count) scenario\(plan.count == 1 ? "" : "s"), about \(total) Jev requests")
        exit(0)
    }
    let scripted = args.has("--scripted")
    if scripted { plan = plan.map { ($0.scenario, 1, $0.requests) } }
    let limit = scripted || args.has("--no-budget") ? Int.max : budget.flatMap { $0 } ?? evalBudget
    if total > limit {
        let costliest = plan.sorted { $0.runs * $0.requests > $1.runs * $1.requests }.prefix(5)
            .map { "  \($0.scenario.file): \($0.runs) × \($0.requests)" }
        fail((["boopdev eval: about \(total) Jev requests, over the budget of \(limit); narrow it with --only or --runs 1, "
               + "raise --budget, or pass --no-budget for the final pass. The costliest:"] + costliest).joined(separator: "\n"))
    }
    let brain: any Brain
    if scripted {
        brain = ExpectBrain()
    } else {
        guard let key = JevKey.environment() else {
            fail("boopdev eval asks Jev, and needs its API key in \(JevKey.variable)")
        }
        brain = JevBrain(key: key)
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
    print("\(plan.count) scenario\(plan.count == 1 ? "" : "s"), about \(total) Jev requests")
    print("every event, view event and pass goes to \(log.path)")
    var results: [[Eval.Result]] = []
    var gapsFailed = 0
    var failed = false
    for (scenario, runs, _) in plan {
        var rs: [Eval.Result] = []
        for _ in 1...runs {
            do { rs.append(try await runner.run(scenario)) } catch { fail("\(error)") }
        }
        results.append(rs)
        if !rs.allSatisfy(\.passed) {
            if scenario.gap != nil { gapsFailed += 1 } else { failed = true }
        }
        for line in Eval.report(rs, story: scenario.story, gap: scenario.gap) { print(line) }
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
    print("every event and pass, with its state: \(log.path)")
    exit(failed ? 1 : 0)
}

func prompts(_ raw: [String]) async {
    let args = arguments("prompts", raw, options: ["--only", "--scenarios", "--steering", "--out"])
    let repo = findRepo()
    func path(_ option: String, _ inRepo: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        guard let repo else { fail("boopdev prompts: can't find the Boop repo; run it inside the repo, or pass --scenarios, --steering and --out") }
        return repo.appendingPathComponent(inRepo)
    }
    var list: [Scenario]
    do { list = try Scenario.load(directory: path("--scenarios", "characters/boop/evals")) } catch { fail("can't read the scenarios: \(error)") }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    let steeringDir = path("--steering", "characters/boop/steering")
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
    let pack = steeringDir.standardizedFileURL.deletingLastPathComponent().lastPathComponent
    let data = JSONLine.encode(["pack": pack, "heads": heads, "questions": questions, "scenarios": scenarios] as [String: Any])
    let out = path("--out", "characters/studio/prompts.js")
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

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
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
