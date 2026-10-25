import AgentHooks
import Dispatch
import Foundation

extension Runtime {
    /// Who a demo's answers and moods are by, in the transcript and the log.
    public static let demoBy = "demo"

    /// After a demo's last step, time for what it starts to play out.
    public static let demoTail = 6.0

    /// Whether an agent's process still runs: a demo's made-up agent's
    /// always does (`DemoPlayer.agentProcess`).
    static func agentRuns(_ process: AgentProcess) -> Bool {
        process == DemoPlayer.agentProcess || AgentProcess.isRunning(process)
    }

    /// Readies a demo script (`DemoScript`) to play: its steps in order,
    /// each when the one before it has ended, from `start()` on. The
    /// person's steps are a poke and talk as the socket's dev messages make
    /// them, and the brain's are a forced pass, so the outputs keep their
    /// own rules.
    ///
    /// The agent's steps are the only ones that differ. With no agent
    /// (`live` false), the player is the agent: it sends each step's hooks
    /// as the agent would, through the same door as real ones. With a live
    /// one, it waits for the agent's own hooks for each step, so the rest
    /// keeps to the agent's pace however fast or slow it goes; a hook the
    /// script doesn't have passes by. It hears them from now on, so an
    /// agent may start before `start()`, while the device is awaited.
    ///
    /// `cursor`, if given, is a file that holds the number of the step
    /// due now (from 0): -1 until `start()`, and the number of steps once
    /// it's over, for whatever keeps a live agent in step. `step` hears
    /// each step as it happens, with the agent's name, and `done` the end,
    /// both on `home`.
    public func demo(_ script: DemoScript, live: Bool = false, cursor: URL? = nil,
                     step: @escaping @Sendable (DemoScript.Step, _ agent: String) -> Void = { _, _ in },
                     done: @escaping @Sendable () -> Void = {}) -> DemoPlayer {
        let player = DemoPlayer(script: script, live: live, cursor: cursor, runtime: self, heardStep: step, done: done)
        demoHeard = live ? { [player] in player.heard($0) } : nil
        player.publish(-1)
        return player
    }

    /// A demo's person back at the Mac after `ms` away: the away and the
    /// back the presence detector would have made, both at once and both
    /// `demo`'s. Being away shows nothing, and the Mac's own keys and mouse
    /// would end an away the script left open.
    func cameBack(afterMs ms: Int64) {
        let now = options.clock()
        recordPresence(PresenceDetector.awayEvent(why: Self.demoBy, since: now - ms, at: now))
        recordPresence(PresenceDetector.backEvent(why: Self.demoBy, at: now))
    }

    /// Readies a demo and plays it at once.
    public func play(_ script: DemoScript, live: Bool = false, cursor: URL? = nil,
                     step: @escaping @Sendable (DemoScript.Step, _ agent: String) -> Void = { _, _ in },
                     done: @escaping @Sendable () -> Void = {}) {
        demo(script, live: live, cursor: cursor, step: step, done: done).start()
    }
}

/// Walks a script's steps in order on the runtime's home queue.
public final class DemoPlayer: @unchecked Sendable {
    let script: DemoScript
    let live: Bool
    let cursor: URL?
    /// Weak: a step waiting to play when its runtime is let go of (a test
    /// ending, the app quitting) does nothing.
    weak var runtimeIfAny: Runtime?
    var runtime: Runtime { runtimeIfAny! }
    let heardStep: @Sendable (DemoScript.Step, String) -> Void
    let done: @Sendable () -> Void
    var index = 0
    /// The agent's hooks since the last one a step was waiting for.
    var hooks: [HookLine] = []
    /// The agent step waiting for its hook, and what to do when it comes.
    var waiting: (matches: (HookLine) -> Bool, then: () -> Void)?
    /// The agent playing the script's: the script's, until a live one's
    /// hooks say who it is.
    lazy var agent = script.agent
    /// The agent a step is about: a live one's, else its buddy's agent's.
    func agent(of step: DemoScript.Step) -> String { live ? agent : script.agent(of: step.buddy) }

    /// With no agent: whether each buddy's agent's main thread's turn is
    /// going (`""` for the only one).
    var turnOpen: Set<String> = []
    /// The named sessions started so far, `buddy/session`.
    var sessions: Set<String> = []
    /// The reviewers sent off and not yet back, by session (`buddy/session`),
    /// each by its `agent_id`, the first sent the first back.
    var reviewers: [String: [String]] = [:]
    var calls = 0
    /// The runtime's labeler before the script's went in front of it.
    var labelerBefore: (any PromptLabeler)?

    init(script: DemoScript, live: Bool, cursor: URL?, runtime: Runtime,
         heardStep: @escaping @Sendable (DemoScript.Step, String) -> Void, done: @escaping @Sendable () -> Void) {
        self.script = script
        self.live = live
        self.cursor = cursor
        self.runtimeIfAny = runtime
        self.heardStep = heardStep
        self.done = done
    }

    /// Plays the script, on `home`.
    public func start() {
        runtime.options.log("demo: \(script.steps.count) steps\(live ? ", with a live agent" : "")")
        // The script's prompts read as it says, on any Mac.
        let readings = Dictionary(script.steps.compactMap { step -> (String, PromptReading.Labels)? in
            guard case .agent(let a) = step.what, let text = a.text, let reading = a.reading else { return nil }
            return (Scrubber.scrub(text), reading)
        }, uniquingKeysWith: { first, _ in first })
        // In front of the app's own labeler until the demo is over.
        labelerBefore = runtime.labeler
        if !readings.isEmpty { runtime.labeler = ScriptLabeler(readings: readings, otherwise: labelerBefore) }
        if !live {
            for buddy in script.buddies.isEmpty ? [nil] : script.buddies.map(\.place) {
                send("SessionStart", buddy: buddy) { $0.source = "startup" }
            }
        }
        next()
    }

    var home: DispatchQueue { runtime.home }
    func later(_ seconds: Double, _ work: @escaping () -> Void) {
        home.asyncAfter(deadline: .now() + max(0, seconds)) { [weak self] in
            guard self?.runtimeIfAny != nil else { return }
            work()
        }
    }

    func publish(_ n: Int) {
        guard let cursor else { return }
        try? "\(n)\n".write(to: cursor, atomically: true, encoding: .utf8)
    }

    /// The next step, `after` the one before ended; the end, after the last.
    func next() {
        guard index < script.steps.count else {
            publish(script.steps.count)
            later(Runtime.demoTail) { [self] in
                runtime.options.log("demo: over")
                runtime.demoHeard = nil
                runtime.labeler = labelerBefore
                done()
            }
            return
        }
        let step = script.steps[index]
        // A live agent's step is due at once: the agent keeps its own pace.
        let wait: Double = if case .agent = step.what, live { 0 } else { step.after }
        later(wait) { [self] in
            publish(index)
            perform(step) { [self] in
                index += 1
                next()
            }
        }
    }

    func perform(_ step: DemoScript.Step, then: @escaping () -> Void) {
        switch step.what {
        case .poke:
            heardStep(step, agent(of: step))
            runtime.tapped(who: Runtime.demoBy, buddy: step.buddy)
            then()
        case .press:
            heardStep(step, agent(of: step))
            runtime.pressed(who: Runtime.demoBy, buddy: step.buddy)
            then()
        case .hold:
            // The board tells the Mac once the finger has been down its
            // hold; the demo's finger stays a little longer.
            heardStep(step, agent(of: step))
            later(DemoScript.holdSeconds) { [self] in
                runtime.gestured(Core.dismissGesture, who: Runtime.demoBy, buddy: step.buddy)
                then()
            }
        case .wait(let ms):
            heardStep(step, agent(of: step))
            runtime.advanceClock(ms, who: Runtime.demoBy)
            then()
        case .talk(let words, let hold):
            heardStep(step, agent(of: step))
            runtime.listen(true, who: Runtime.demoBy, buddy: step.buddy)
            later(hold) { [self] in
                runtime.heard(words, by: .app, who: Runtime.demoBy, to: step.buddy)
                then()
            }
        case .back(let ms):
            heardStep(step, agent)
            runtime.cameBack(afterMs: ms)
            then()
        case .brain(let answers, let mood):
            if !answers.isEmpty { runtime.forcePass(answers, by: Runtime.demoBy, who: Runtime.demoBy, buddy: step.buddy) }
            if let mood { runtime.forceMood(mood, by: Runtime.demoBy, who: Runtime.demoBy, buddy: step.buddy) }
            then()
        case .agent(let a):
            if live {
                waitFor(endOf(a)) { [self] in
                    heardStep(step, agent(of: step))
                    then()
                }
            } else {
                act(a, step: step, then: then)
            }
        }
    }

    // MARK: A live agent

    /// The hook that ends an agent step: its turn's start, a tool's end of
    /// the right kind, the reviewer's start or report, the session's start
    /// once its context is compacted, or the turn's end.
    func endOf(_ a: DemoScript.Step.Agent) -> (HookLine) -> Bool {
        func toolEnd(_ kinds: Set<ToolKind>) -> (HookLine) -> Bool {
            { Mapping.kind(of: $0).map { $0 == (.tool, .end) } == true && kinds.contains(ToolKind.of($0.tool ?? "")) }
        }
        switch a.does {
        case .prompt: return { $0.hook == "UserPromptSubmit" }
        // Codex reads with a shell command.
        case .read: return { toolEnd([.read])($0) || ($0.agent == "codex" && toolEnd([.shell])($0)) }
        case .edit: return toolEnd([.edit])
        // A request that waits ends its step as it's asked.
        case .run where a.waits: return { Mapping.kind(of: $0).map { $0 == (.tool, .wait) } == true }
        case .run: return toolEnd([.shell])
        case .review: return { $0.hook == "SubagentStart" }
        // Claude's `SessionStart` with the source `compact`, Codex's `PostCompact`.
        case .compact: return { Mapping.event(from: $0)?.source == Mapping.compacted }
        // A whole list (Claude's TodoWrite, Codex's update_plan), or one
        // of Claude's tasks.
        case .todo: return { $0.todosTotal != nil || $0.todoID != nil }
        case .reply: return a.byReviewer ? { $0.hook == "SubagentStop" } : { $0.hook == "Stop" }
        }
    }

    func waitFor(_ matches: @escaping (HookLine) -> Bool, then: @escaping () -> Void) {
        if let i = hooks.firstIndex(where: matches) {
            hooks.removeFirst(i + 1)
            return then()
        }
        waiting = (matches, then)
    }

    /// A hook from the live agent: the end of the step waiting for one, or
    /// kept until a step does. If it ends one of the next agent steps
    /// instead, the agent left out the ones before it (a step it skipped,
    /// or a call it was refused): the script goes on from there, without
    /// what came between, rather than wait for good.
    func heard(_ hook: HookLine) {
        agent = hook.agent
        guard let w = waiting else { return hooks.append(hook) }
        if w.matches(hook) {
            waiting = nil
            hooks.removeAll()
            return w.then()
        }
        let ahead = script.steps.indices.dropFirst(index + 1).filter {
            if case .agent = script.steps[$0].what { true } else { false }
        }.prefix(Self.lookahead)
        guard let j = ahead.first(where: { j in
            if case .agent(let a) = script.steps[j].what { return endOf(a)(hook) }
            return false
        }) else { return hooks.append(hook) }
        runtime.options.log("demo: the agent left out steps \(script.steps[index].number)–\(script.steps[j - 1].number); going on")
        waiting = nil
        hooks.removeAll()
        index = j
        publish(index)
        heardStep(script.steps[j], agent(of: script.steps[j]))
        index += 1
        next()
    }

    /// How many agent steps ahead a hook may end, for the script to skip to it.
    static let lookahead = 3

    /// The process the player's agent is, on every hook it sends, as a real
    /// agent's hooks say theirs: it runs as long as the demo does
    /// (`Runtime.agentRuns`), so a request waits however long the demo's
    /// clock jumps. No real process started 1 ms into 1970.
    public static let agentProcess = AgentProcess(pid: 4242, started: 1)

    // MARK: No agent: the player is it

    /// Sends a hook as the agent would, the buddy `buddy`'s agent's, in its
    /// session `session` (nil for its first), with `set`'s fields. Each
    /// session is its own thread, in a folder of its own.
    func send(_ hook: String, buddy: String? = nil, session name: String? = nil, _ set: (inout HookLine) -> Void = { _ in }) {
        let tail = [buddy, name].compactMap { $0 }.map { "-\($0)" }.joined()
        let session = "demo" + tail
        let cwd = "/demo/\(slug)" + tail
        var line = HookLine(agent: script.agent(of: buddy), hook: hook, session: session, cwd: cwd,
                            process: Self.agentProcess, ts: runtime.options.wallClock())
        set(&line)
        runtime.hook(line, received: runtime.options.clock())
    }

    var slug: String {
        let s = script.title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(s).split(separator: "-").joined(separator: "-").ifEmpty("project")
    }

    func act(_ a: DemoScript.Step.Agent, step: DemoScript.Step, then: @escaping () -> Void) {
        calls += 1
        let buddy = step.buddy
        let codex = script.agent(of: buddy) == "codex"
        // A session the script hasn't used yet starts first, as an agent's would.
        let key = (buddy ?? "") + "/" + (a.session ?? "")
        if let name = a.session, !sessions.contains(key) {
            sessions.insert(key)
            self.send("SessionStart", buddy: buddy, session: name) { $0.source = "startup" }
        }
        func send(_ hook: String, _ set: (inout HookLine) -> Void = { _ in }) { self.send(hook, buddy: buddy, session: a.session, set) }
        let open = key
        let id = "t\(calls)"
        let finish = { [self] in heardStep(step, agent(of: step)); then() }
        // A request that `waits` ends the step as it's asked: the steps
        // after it play while it waits, and you allow it `ask` seconds on.
        func tool(_ name: String, topic: String? = nil, fails: Bool = false, ask: Double? = nil, waits: Bool = false) {
            let call = { (l: inout HookLine) in l.tool = name; l.toolUseID = id; l.topic = topic }
            send("PreToolUse", call)
            let ends = { [self] in
                later(step.takes) { [self] in
                    send(fails && !codex ? "PostToolUseFailure" : "PostToolUse") {
                        call(&$0)
                        if fails { $0.toolError = "exit_code" }
                    }
                    if !waits { finish() }
                }
            }
            guard let ask else { return ends() }
            later(0.2) { [self] in
                send("PermissionRequest") { $0.tool = name; $0.toolUseID = id }
                if waits { finish() }
                later(ask, ends)
            }
        }
        // A turn ended (the reviewer's report starts a new one).
        if a.does != .prompt, !a.byReviewer, !turnOpen.contains(open) {
            send("UserPromptSubmit")
            turnOpen.insert(open)
        }
        switch a.does {
        case .prompt:
            send("UserPromptSubmit") { $0.prompt = a.text ?? "" }
            turnOpen.insert(open)
            finish()
        case .read: tool(codex ? "Bash" : "Read")
        case .edit: tool(codex ? "apply_patch" : "Edit")
        case .run: tool("Bash", topic: a.cmd.flatMap { Topic.tag(command: $0) }, fails: a.fails, ask: a.ask, waits: a.waits)
        case .todo:
            // The whole list, as Claude's TodoWrite and Codex's update_plan
            // give it: the counts, never the items.
            let list = { (l: inout HookLine) in l.tool = codex ? "update_plan" : "TodoWrite"; l.toolUseID = id }
            send("PreToolUse") {
                list(&$0)
                $0.todosDone = a.todos?.done
                $0.todosTotal = a.todos?.total
            }
            later(step.takes) { [self] in
                send("PostToolUse", list)
                finish()
            }
        case .review:
            send("PreToolUse") { $0.tool = "Agent"; $0.toolUseID = id }
            reviewers[key, default: []].append("reviewer-\(id)")
            later(0.2) { [self] in
                send("SubagentStart") { $0.agentID = "reviewer-\(id)" }
                send("PostToolUse") { $0.tool = "Agent"; $0.toolUseID = id }
                finish()
            }
        case .compact:
            // What each agent sends once it has compacted, its compaction
            // taking the step's seconds.
            later(step.takes) { [self] in
                if codex {
                    send("PostCompact")
                } else {
                    send("SessionStart") { $0.source = Mapping.compacted }
                }
                finish()
            }
        case .reply:
            later(step.takes) { [self] in
                if a.byReviewer {
                    let reviewer = reviewers[key]?.isEmpty == false ? reviewers[key]!.removeFirst() : nil
                    send("SubagentStop") { $0.agentID = reviewer }
                } else if a.fails, !codex {
                    // Codex has no hook for a failed turn.
                    send("StopFailure") { $0.error = "api_error" }
                    turnOpen.remove(open)
                } else {
                    send("Stop") { $0.message = a.text ?? "" }
                    turnOpen.remove(open)
                }
                finish()
            }
        }
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

/// A demo's readings: each prompt step's own, by its scrubbed text, and
/// the labeler it stands in front of for any other prompt and every
/// message.
struct ScriptLabeler: PromptLabeler {
    let readings: [String: PromptReading.Labels]
    let otherwise: (any PromptLabeler)?

    func label<Of: ReadingText>(_ text: String, as: Of.Type) async -> Reading<Of>.Labels? {
        if let reading = readings[text] as? Reading<Of>.Labels { return reading }
        return await otherwise?.label(text, as: Of.self)
    }
}
