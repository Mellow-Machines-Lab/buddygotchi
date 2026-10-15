import AgentHooks
import Dispatch
import Foundation

extension Runtime {
    /// Who a demo's answers and moods are by, in the transcript and the log.
    public static let demoBy = "demo"

    /// After a demo's last step, time for what it starts to play out.
    public static let demoTail = 6.0

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
    unowned let runtime: Runtime
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
    /// With no agent: whether the main thread's turn is going.
    var turnOpen = false
    var calls = 0

    init(script: DemoScript, live: Bool, cursor: URL?, runtime: Runtime,
         heardStep: @escaping @Sendable (DemoScript.Step, String) -> Void, done: @escaping @Sendable () -> Void) {
        self.script = script
        self.live = live
        self.cursor = cursor
        self.runtime = runtime
        self.heardStep = heardStep
        self.done = done
    }

    /// Plays the script, on `home`.
    public func start() {
        runtime.options.log("demo: \(script.steps.count) steps\(live ? ", with a live agent" : "")")
        if !live { send("SessionStart") { $0.source = "startup" } }
        next()
    }

    var home: DispatchQueue { runtime.home }
    func later(_ seconds: Double, _ work: @escaping () -> Void) {
        home.asyncAfter(deadline: .now() + max(0, seconds), execute: work)
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
            heardStep(step, agent)
            runtime.tapped(who: Runtime.demoBy)
            then()
        case .talk(let words, let hold):
            heardStep(step, agent)
            runtime.listen(true, who: Runtime.demoBy)
            later(hold) { [self] in
                runtime.heard(words, by: .app, who: Runtime.demoBy)
                then()
            }
        case .brain(let answers, let mood):
            if !answers.isEmpty { runtime.forcePass(answers, by: Runtime.demoBy, who: Runtime.demoBy) }
            if let mood { runtime.forceMood(mood, by: Runtime.demoBy, who: Runtime.demoBy) }
            then()
        case .agent(let a):
            if live {
                waitFor(endOf(a)) { [self] in
                    heardStep(step, agent)
                    then()
                }
            } else {
                act(a, step: step, then: then)
            }
        }
    }

    // MARK: A live agent

    /// The hook that ends an agent step: its turn's start, a tool's end of
    /// the right kind, the reviewer's start or report, or the turn's end.
    func endOf(_ a: DemoScript.Step.Agent) -> (HookLine) -> Bool {
        func toolEnd(_ kinds: Set<ToolKind>) -> (HookLine) -> Bool {
            { Mapping.kind(of: $0).map { $0 == (.tool, .end) } == true && kinds.contains(ToolKind.of($0.tool ?? "")) }
        }
        switch a.does {
        case .prompt: return { $0.hook == "UserPromptSubmit" }
        // Codex reads with a shell command.
        case .read: return { toolEnd([.read])($0) || ($0.agent == "codex" && toolEnd([.shell])($0)) }
        case .edit: return toolEnd([.edit])
        case .run: return toolEnd([.shell])
        case .review: return { $0.hook == "SubagentStart" }
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
        heardStep(script.steps[j], agent)
        index += 1
        next()
    }

    /// How many agent steps ahead a hook may end, for the script to skip to it.
    static let lookahead = 3

    // MARK: No agent: the player is it

    /// Sends a hook as the agent would, with `set`'s fields.
    func send(_ hook: String, _ set: (inout HookLine) -> Void = { _ in }) {
        var line = HookLine(agent: script.agent, hook: hook, session: "demo", cwd: "/demo/\(slug)", ts: runtime.options.wallClock())
        set(&line)
        runtime.hook(line, received: runtime.options.clock())
    }

    var slug: String {
        let s = script.title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(s).split(separator: "-").joined(separator: "-").ifEmpty("project")
    }

    func act(_ a: DemoScript.Step.Agent, step: DemoScript.Step, then: @escaping () -> Void) {
        calls += 1
        let codex = script.agent == "codex"
        let id = "t\(calls)"
        let finish = { [self] in heardStep(step, agent); then() }
        func tool(_ name: String, topic: String? = nil, fails: Bool = false, ask: Double? = nil) {
            let call = { (l: inout HookLine) in l.tool = name; l.toolUseID = id; l.topic = topic }
            send("PreToolUse", call)
            let ends = { [self] in
                later(step.takes) { [self] in
                    send(fails && !codex ? "PostToolUseFailure" : "PostToolUse") {
                        call(&$0)
                        if fails { $0.toolError = "exit_code" }
                    }
                    finish()
                }
            }
            guard let ask else { return ends() }
            later(0.2) { [self] in
                send("PermissionRequest") { $0.tool = name; $0.toolUseID = id }
                later(ask, ends)
            }
        }
        // A turn ended (the reviewer's report starts a new one).
        if a.does != .prompt, !a.byReviewer, !turnOpen {
            send("UserPromptSubmit")
            turnOpen = true
        }
        switch a.does {
        case .prompt:
            send("UserPromptSubmit") { $0.prompt = a.text ?? "" }
            turnOpen = true
            finish()
        case .read: tool(codex ? "Bash" : "Read")
        case .edit: tool(codex ? "apply_patch" : "Edit")
        case .run: tool("Bash", topic: a.cmd.flatMap { Topic.tag(command: $0) }, fails: a.fails, ask: a.ask)
        case .review:
            send("PreToolUse") { $0.tool = "Agent"; $0.toolUseID = id }
            later(0.2) { [self] in
                send("SubagentStart")
                send("PostToolUse") { $0.tool = "Agent"; $0.toolUseID = id }
                finish()
            }
        case .reply:
            later(step.takes) { [self] in
                if a.byReviewer {
                    send("SubagentStop")
                } else {
                    send("Stop") { $0.message = a.text ?? "" }
                    turnOpen = false
                }
                finish()
            }
        }
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
