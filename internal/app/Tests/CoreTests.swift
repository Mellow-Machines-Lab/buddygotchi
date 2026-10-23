import AgentHooks
import BoopDevKit
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The hooks the rig sends, by what they mean to the rules: each becomes
/// the raw event its hook does.
enum Hook: String, CaseIterable {
    case sessionStart, turnStart, activity, needsYou, turnEnd, turnFailed, turnStopped, subagentStart, subagentEnd,
         sessionEnd
}

/// What one input did: the core's effects and the view events made. An
/// array literal is effects alone.
struct Fx: Equatable, ExpressibleByArrayLiteral {
    var effects: [CoreEffect] = []
    var views: [ViewEvent] = []

    init(_ step: Pipeline.Step) {
        effects = step.effects
        views = step.views
    }

    init() {}

    init(arrayLiteral effects: CoreEffect...) { self.effects = effects }

    static func + (a: Fx, b: Fx) -> Fx {
        var out = a
        out.effects += b.effects
        out.views += b.views
        return out
    }

    static func += (a: inout Fx, b: Fx) { a = a + b }

    func contains(_ effect: CoreEffect) -> Bool { effects.contains(effect) }
    func contains(where predicate: (CoreEffect) -> Bool) -> Bool { effects.contains(where: predicate) }
}

extension ViewEvent {
    /// What the rules did about it, as far as the view event has it when
    /// it's made: a turn's start has its `starting` reaction.
    var reaction: String? { did.first { $0.by == "rule" }?.message }
}

/// Drives a pipeline (a core and a view) with a virtual clock. Starts
/// 2026-10-14 14:00 UTC, a Wednesday afternoon, with today already started.
final class CoreRig {
    static let start = Replay.defaultStart
    static let day: Int64 = 24 * 3600 * 1000
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    var now: Int64
    let pipeline: Pipeline
    var core: Core { pipeline.core }
    var view: TranscriptView { pipeline.view }
    var log: [CoreEffect] = []
    var views: [ViewEvent] = []

    init(start: Int64 = CoreRig.start, newDay: Bool = false, seed: UInt64 = 1, rules: Personality.Rules = Personality.Rules()) {
        now = start
        let today = time.day(start)
        let core = Core(config: .init(time: time), lastActiveDay: newDay ? nil : today)
        pipeline = Pipeline(core: core, view: TranscriptView(rules: rules, seed: seed))
        if !newDay { core.tick(at: start) }  // the first snapshot has gone out
    }

    /// The mood output's change, as the runtime hands it on: the core
    /// reads `mood` from now, and publishes it.
    @discardableResult
    func setMood(_ mood: String) -> [CoreEffect] {
        core.mood = { mood }
        return core.moodChanged(at: now)
    }

    /// The raw event a hook of `kind` makes, as the adapter would.
    func event(_ kind: Hook, _ agent: Agent = .claude, session: String = "s1", subagent: String? = nil,
               project: String = "landing", workspace: String? = nil, tool: String? = nil, topic: String? = nil,
               failed: Bool? = nil, notice: Bool? = nil, kind noticeKind: String? = nil, id: String? = nil,
               done: Bool? = nil, error: String? = nil, message: String? = nil, prompt: String? = nil,
               source: String? = nil, mode: String? = nil, app: String? = nil, appSession: String? = nil) -> Event {
        var data: [String: JSONValue] = [:]
        func put(_ key: String, _ value: String?) { if let value { data[key] = .string(value) } }
        put("app", app)
        put("app_session", appSession)
        put("tool", tool)
        put("tool_use_id", id)
        put("topic", topic)
        put("mode", mode)
        let type: Event.Kind
        let phase: Event.Phase
        let specific: String
        switch kind {
        case .sessionStart:
            (type, phase, specific) = (.session, .start, "SessionStart")
            put("source", source)
        case .sessionEnd: (type, phase, specific) = (.session, .end, "SessionEnd")
        case .turnStart:
            (type, phase, specific) = (.turn, .start, "UserPromptSubmit")
            put("prompt", prompt)
        case .turnEnd:
            (type, phase, specific) = (.turn, .end, "Stop")
            data["outcome"] = "done"
            put("message", message)
        case .turnFailed:
            (type, phase, specific) = (.turn, .end, "StopFailure")
            data["outcome"] = "failed"
            put("error", error)
        case .turnStopped:
            // Esc on a call, or Claude's idle notice (`notice: true`).
            (type, phase) = (.turn, .end)
            data["outcome"] = "stopped"
            if notice == true { data["notice"] = .string(noticeKind ?? "idle_prompt") }
            specific = notice == true ? "Notification" : agent == .codex ? "Interrupt" : "PostToolUseFailure"
        case .activity:
            // A result (failed or not) is a finished call: its `PostToolUse`.
            if done ?? (failed != nil) {
                (type, phase) = (.tool, .end)
                specific = failed == true ? "PostToolUseFailure" : "PostToolUse"
                if let failed { data["failed"] = .bool(failed) }
                if failed == true { data["error"] = .string(error ?? "exit_code") }
            } else if tool == nil {
                (type, phase, specific) = (.tool, .end, "ElicitationResult")
            } else {
                (type, phase, specific) = (.tool, .start, "PreToolUse")
            }
        case .needsYou:
            // A tool-less request is Claude's `Notification` unless it says
            // otherwise (`notice: false` is an `Elicitation`).
            (type, phase) = (.tool, .wait)
            let asNotice = notice ?? (tool == nil)
            if asNotice { data["notice"] = .string(noticeKind ?? "permission_prompt") }
            let input = asNotice ? data["notice"]?.string == "elicitation_dialog" : tool == nil
            data["asking"] = .string(input ? "input" : "permission")
            specific = asNotice ? "Notification" : tool == nil ? "Elicitation" : "PermissionRequest"
        case .subagentStart: (type, phase, specific) = (.subagent, .start, "SubagentStart")
        case .subagentEnd: (type, phase, specific) = (.subagent, .end, "SubagentStop")
        }
        let cwd = workspace.map { "/rig/\(project)/.worktrees/\($0)" } ?? "/rig/\(project)"
        return Event(at: now, source: Event.Source(agent), type: type, phase: phase, specificType: specific,
                     session: session, subagent: subagent, cwd: cwd, data: data)
    }

    @discardableResult
    func send(_ kind: Hook, _ agent: Agent = .claude, session: String = "s1", subagent: String? = nil,
              project: String = "landing", workspace: String? = nil, tool: String? = nil, topic: String? = nil,
              failed: Bool? = nil, notice: Bool? = nil, kind noticeKind: String? = nil, id: String? = nil,
              done: Bool? = nil, error: String? = nil, message: String? = nil, prompt: String? = nil,
              source: String? = nil, mode: String? = nil, app: String? = nil, appSession: String? = nil) -> Fx {
        send(event(kind, agent, session: session, subagent: subagent, project: project, workspace: workspace, tool: tool,
                   topic: topic, failed: failed, notice: notice, kind: noticeKind, id: id, done: done, error: error,
                   message: message, prompt: prompt, source: source, mode: mode, app: app, appSession: appSession))
    }

    @discardableResult
    func send(_ event: Event) -> Fx {
        sent.append(event)
        return note(Fx(pipeline.agentReadingPrompt(event)))
    }

    /// Every event sent, in order.
    var sent: [Event] = []

    /// A poke from the device.
    @discardableResult
    func poke() -> Fx { note(Fx(pipeline.poke(at: now))) }

    /// What push-to-talk heard, after `by`'s button.
    @discardableResult
    func said(_ words: String, by: Core.Talker = .device) -> Fx { note(Fx(pipeline.said(words, by: by, at: now))) }

    /// The device's BOOT button held for push-to-talk (`talk_on`), or let
    /// go (`talk_off`).
    @discardableResult
    func talk(_ on: Bool) -> Fx {
        note(Fx(pipeline.effects(core.listen(on, by: .device, at: now), at: now)))
    }

    /// A pass is over, about the event `seq`, with a reaction or not: for
    /// push-to-talk's reply.
    @discardableResult
    func passed(about seq: Int? = nil, reacted: Bool) -> Fx {
        note(Fx(pipeline.effects(core.passed(about: seq, reacted: reacted, at: now), at: now)))
    }

    /// Boop starts a reaction, as the harness records one.
    func react() {
        pipeline.record(Event.action(at: now, phase: .start, name: ReactOutput.outputName,
                              data: ["for": .null, "by": "brain", "ok": true, "message": "Boop made a happy face."]))
    }

    /// Moves the clock, ticking once a second like the app does, or every
    /// `step` ms where a test waits out a day for what only a day does.
    @discardableResult
    func wait(_ ms: Int64, every step: Int64 = 1000) -> Fx {
        var fx = Fx()
        let end = now + ms
        while now < end {
            now = min(end, now + step)
            fx += note(Fx(pipeline.tick(at: now)))
        }
        return fx
    }

    func note(_ fx: Fx) -> Fx {
        log += fx.effects
        views += fx.views
        return fx
    }

    /// A whole turn in one session: prompt, `ms` of work, finish.
    @discardableResult
    func turn(_ ms: Int64, session: String = "s1", agent: Agent = .claude) -> Fx {
        send(.turnStart, agent, session: session)
        wait(ms)
        return send(.turnEnd, agent, session: session)
    }

    var state: StateSnapshot { core.snapshot(at: now) }
    /// The popover's list, as `[agent, project, status]`.
    var sessions: [[String]] { core.sessionList(at: now).map { [$0.agent, $0.project, $0.status.rawValue] } }
    /// The rule actions recorded, by name, in order.
    var ruleActions: [String] {
        pipeline.transcript.events.filter { $0.isAction && $0["by"]?.string == "rule" }
            .map { $0.actionName + ($0.actionPhase.map { " " + $0.rawValue } ?? "") }
    }
}

/// The view events made, in order.
func events(_ fx: Fx) -> [ViewEvent] { fx.views }

/// The outcomes of the turn ends that woke the brain: no rule celebrates
/// a finish, so this is how a finish reaches Boop.
func finished(_ fx: Fx) -> [String] {
    events(fx).filter { $0.name == "turn end" && $0.wakesBrain }.compactMap(\.facts["outcome"]?.string)
}

/// The view events that wake the brain, by their lines.
func woke(_ fx: Fx) -> [String] {
    events(fx).filter(\.wakesBrain).map(\.line)
}

/// A chatty Boop's rules, for tests that need the working heartbeat often.
extension Personality.Rules {
    static let chatty = Personality.Rules(workBeatMs: 45_000...90_000, toolUses: .notable)
}

/// The working heartbeats' lines: no rule mumbles,
/// so this is how a quiet stretch of work reaches the brain.
func workBeats(_ fx: Fx) -> [String] {
    events(fx).filter { $0.type == .heartbeat && $0.facts["working_ms"] != nil }.map(\.line)
}

/// A new, empty directory under the system's temporary one, named
/// `<prefix>-<UUID>`. The test removes it.
func tempDir(_ prefix: String) -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func states(_ fx: Fx) -> [StateSnapshot] { states(fx.effects) }

/// The threads the rules opened on the Mac.
func opened(_ fx: Fx) -> [ThreadRef] {
    fx.effects.compactMap { if case .open(let t) = $0 { return t } else { return nil } }
}

func states(_ fx: [CoreEffect]) -> [StateSnapshot] {
    fx.compactMap { if case .state(let s) = $0 { return s } else { return nil } }
}

/// The rules' reactions sent.
func deviceReactions(_ fx: Fx) -> [DeviceReaction] { deviceReactions(fx.effects) }

func deviceReactions(_ fx: [CoreEffect]) -> [DeviceReaction] {
    fx.compactMap { if case .reaction(let m) = $0 { return m } else { return nil } }
}

/// The rule reactions as `anim` or `anim ctx`, for short checks.
func reactionNames(_ fx: Fx) -> [String] {
    deviceReactions(fx).map { ([$0.anim ?? "-"] + [$0.ctx].compactMap { $0 }).joined(separator: " ") }
}

// MARK: - Agent work

final class CoreAgentWorkTests: XCTestCase {
    func testSendingAPromptMakesBaseWorking() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(rig.state.base, "idle")
        let fx = rig.send(.turnStart)
        XCTAssertEqual(states(fx).last?.base, "working")
        XCTAssertEqual(states(fx).last?.busy, 1)
        XCTAssertEqual(woke(fx), [#"claude started turn 1 on "landing"."#])
        XCTAssertNil(events(fx).first?.reaction, "a turn start's reaction is in the log, not HISTORY")
    }

    /// No rule celebrates a finish, whatever its length.
    /// It goes idle, and the brain hears of it with no rule reaction, so
    /// whether it's celebrated is the brain's call.
    func testAFinishedTurnReachesTheBrainWithNoRuleReaction() {
        for ms: Int64 in [29_000, 300_000, 1_199_000] {
            let rig = CoreRig()
            XCTAssertEqual(finished(rig.turn(ms)), ["done"], "\(ms) ms")
            XCTAssertEqual(rig.state.base, "idle")
        }
        let rig = CoreRig()
        let fx = rig.turn(1_200_000)
        XCTAssertEqual(finished(fx), ["done"], "one size")
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": done, a very long turn, no tool calls."#])
        XCTAssertNil(events(fx).first?.reaction, "no rule cheers")
        XCTAssertEqual(events(fx).first?.facts["length_ms"], .int(1_200_000))
    }

    func testAFinishReachesTheBrainWhileOthersKeepWorking() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(10_000)
        XCTAssertEqual(finished(rig.send(.turnEnd, session: "a")), ["done"])
        XCTAssertEqual(rig.state.base, "working")
    }

    /// Each finish reaches the brain on its own.
    func testSeveralFinishingAtOnceEachReachTheBrain() {
        let rig = CoreRig()
        for s in ["a", "b", "c"] { rig.send(.turnStart, session: s) }
        rig.wait(400_000)
        XCTAssertEqual(finished(rig.send(.turnEnd, session: "a")), ["done"])
        rig.wait(1000)
        XCTAssertEqual(finished(rig.send(.turnEnd, session: "b")), ["done"])
        XCTAssertEqual(finished(rig.send(.turnEnd, session: "c")), ["done"])
    }

    /// A turn you interrupt ends without `Stop`, so the
    /// interrupt (or Claude sitting at its prompt) ends it: idle at once,
    /// with the rules' `stopped` reaction, no working
    /// heartbeat after, and the brain hears of a stopped turn.
    func testAnInterruptedTurnGoesIdleQuietly() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        let fx = rig.send(.turnStopped, tool: "Bash")
        XCTAssertEqual(reactionNames(fx), ["stopped"])
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(events(fx).map { $0.facts["outcome"] }, ["stopped"])
        XCTAssertEqual(workBeats(rig.wait(10 * 60_000)), [], "no working heartbeat")

        rig.send(.turnStart, session: "s2")
        rig.send(.needsYou, session: "s2", tool: "Bash")
        rig.send(.turnStopped, session: "s2", tool: "Bash")
        XCTAssertNil(rig.state.attn, "an interrupted call answers it, as any event does")
        XCTAssertEqual(rig.state.base, "idle")
    }

    /// Esc on Claude's permission prompt sends no hook, and
    /// Claude's idle notice about a minute later means it sits at its own
    /// prompt with the turn over, which never happens while a prompt is up,
    /// a subagent's included. So the notice answers every asker: the main
    /// agent, a Notification alone, or subagents. Before,
    /// a subagent's request stayed, and the notice restarted the safety
    /// net's ten minutes, so Boop stayed amber about 11 minutes after Esc.
    func testClaudesIdleNoticeAnswersEveryRequest() {
        for asker in ["main agent", "notification alone"] {
            let rig = CoreRig(rules: .chatty)
            rig.send(.turnStart)
            rig.send(.needsYou, tool: asker == "main agent" ? "Bash" : nil)
            rig.wait(61_000)
            XCTAssertNotNil(rig.state.attn, asker)
            let fx = rig.send(.turnStopped)
            XCTAssertNil(states(fx).last?.attn, asker)
            XCTAssertEqual(rig.state.base, "idle", asker)
            XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]], asker)
            XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": stopped, a long turn, no tool calls."#],
                           "\(asker): the notice answered the request before the stop applied")
            XCTAssertEqual(workBeats(rig.wait(10 * 60_000)), [], "\(asker): no working heartbeat")
        }
        for askers in [["a1"], ["", "a1"], ["a1", "a2"]] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.activity, tool: "Agent")
            for a in askers { rig.send(.needsYou, subagent: a.isEmpty ? nil : a, tool: "Bash") }
            rig.wait(60_000)
            let fx = rig.send(.turnStopped, notice: true)
            XCTAssertNil(states(fx).last?.attn, "\(askers)")
            XCTAssertEqual(rig.state.base, "idle", "\(askers)")
            XCTAssertEqual(events(fx).map { $0.facts["outcome"] }, ["stopped"], "\(askers)")
        }
    }

    /// A turn that stopped or ended stays over when the
    /// result of a call that started before then lands just after it: Esc
    /// as a parallel call finished, a subagent's call racing the interrupt,
    /// or Codex's aborted command after its `Interrupt`. The result still
    /// counts, but the session stays idle, with no working heartbeat, and only one
    /// stopped turn is recorded. A call that starts afterwards works again.
    func testALateResultDoesntRestartAStoppedTurn() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Read", id: "r")
        rig.send(.activity, tool: "Bash", id: "b")
        rig.wait(500)
        XCTAssertEqual(events(rig.send(.turnStopped, tool: "Bash")).map { $0.facts["outcome"] }, ["stopped"])
        rig.now += 50
        rig.send(.activity, tool: "Read", failed: false, id: "r")
        XCTAssertEqual(rig.state.base, "idle", "the parallel Read's result")
        XCTAssertEqual(workBeats(rig.wait(60_000)), [], "no working heartbeat")
        XCTAssertEqual(events(rig.send(.turnStopped, notice: true)), [], "one stopped turn, not two")

        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent", id: "ta")
        rig.send(.activity, tool: "Agent", id: "tb")
        rig.send(.activity, subagent: "A", tool: "Bash", id: "a1")
        rig.send(.activity, subagent: "B", tool: "Bash", id: "b1")
        rig.wait(1000)
        var ends = events(rig.send(.turnStopped, subagent: "A", tool: "Bash"))
        ends += events(rig.send(.activity, subagent: "B", tool: "Bash", failed: false, id: "b1"))
        ends += events(rig.send(.turnStopped, tool: "Agent"))
        ends += events(rig.send(.turnStopped, tool: "Agent"))
        XCTAssertEqual(ends.map { $0.facts["outcome"] }, ["stopped"])
        XCTAssertEqual(rig.state.base, "idle")

        rig.send(.turnStart, .codex, session: "c")
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1")
        rig.wait(500)
        rig.send(.turnStopped, .codex, session: "c")  // Interrupt
        rig.now += 50
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1", done: true)
        XCTAssertEqual(rig.state.base, "idle", "Codex has no idle notice to put it right")
        rig.wait(600_000)
        XCTAssertEqual(rig.state.base, "idle")

        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c2")
        XCTAssertEqual(rig.state.base, "working", "a call that starts afterwards")
    }

    /// The safety net clears a request after ten silent
    /// minutes and makes the session idle, but its turn is still open: you
    /// may have approved (which sends no hook) and the command run on. So
    /// an interrupt after it still ends that turn as stopped, and the
    /// brain hears of it, and the aborted call's
    /// result is then a late one that doesn't start the turn again. Before,
    /// the stop was dropped for a session no longer working, and the late
    /// result made it work, with working heartbeats, for up to an hour.
    func testAStopAfterTheSafetyNetEndsTheOpenTurn() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart, .codex, session: "c")
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1")
        rig.send(.needsYou, .codex, session: "c", tool: "shell")
        rig.wait(3000)
        XCTAssertNotNil(rig.state.attn)
        rig.wait(660_000)
        XCTAssertNil(rig.state.attn, "the safety net")
        XCTAssertEqual(rig.state.base, "idle")
        let fx = rig.send(.turnStopped, .codex, session: "c")  // Interrupt
        XCTAssertEqual(woke(fx), [#"codex finished turn 1 on "landing": stopped, a very long turn, no tool calls."#])
        rig.now += 50
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1", done: true)
        XCTAssertEqual(rig.state.base, "idle", "the aborted command's result is late")
        XCTAssertEqual(workBeats(rig.wait(30 * 60_000)), [], "no working heartbeat")
        XCTAssertEqual(rig.state.base, "idle")

        // Claude: a subagent asks, the safety net clears it, and Esc
        // interrupts the subagent's call while a sibling's result races it;
        // or Claude's idle notice comes instead.
        for stop in ["interrupt", "idle notice"] {
            let rig = CoreRig(rules: .chatty)
            rig.send(.turnStart)
            rig.send(.activity, tool: "Task", id: "t")
            rig.send(.activity, subagent: "a1", tool: "Bash", id: "b")
            rig.send(.needsYou, subagent: "a1", tool: "Bash")
            rig.send(.needsYou)
            rig.send(.activity, subagent: "a2", tool: "Grep", id: "g")
            rig.wait(12 * 60_000 + 30_000)
            XCTAssertNil(rig.state.attn, stop)
            let fx = stop == "interrupt" ? rig.send(.turnStopped, subagent: "a1", tool: "Bash")
                : rig.send(.turnStopped, notice: true)
            XCTAssertEqual(events(fx).map { $0.facts["outcome"] }, ["stopped"], stop)
            rig.send(.activity, subagent: "a2", tool: "Grep", failed: false, id: "g")
            XCTAssertEqual(rig.state.base, "idle", stop)
            XCTAssertEqual(events(rig.send(.turnStopped, notice: true)), [], "\(stop): one stopped turn, not two")
        }
    }

    /// A stop with no turn open is never an event,
    /// and a finish is the same: a `Stop` after the turn stopped, a second
    /// `Stop`, or one from a session Boop has only now seen (launched, or
    /// forgotten after a day, partway through) finishes nothing Boop saw.
    /// It gets no event. Before, each read "done, a short turn"
    /// (turn 0 for a new session).
    func testAFinishWithNoTurnOpenIsNothing() {
        let rig = CoreRig()
        rig.send(.turnStart, .codex, session: "c")
        rig.send(.activity, .codex, session: "c", tool: "shell")
        rig.wait(2000)
        XCTAssertEqual(events(rig.send(.turnStopped, .codex, session: "c")).count, 1)  // Interrupt
        var fx = rig.send(.turnEnd, .codex, session: "c")
        fx += rig.send(.turnFailed, .codex, session: "c")
        XCTAssertEqual(events(fx), [], "after the stop")

        rig.send(.turnStart)
        rig.wait(20_000)
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
        rig.wait(3000)
        fx = rig.send(.turnEnd)
        XCTAssertEqual(events(fx), [], "a second Stop")

        for kind in [Hook.turnEnd, .turnFailed] {
            let fx = rig.send(kind, session: "new-\(kind.rawValue)")
            XCTAssertEqual(events(fx), [], "\(kind.rawValue) from a session never seen")
        }
        rig.send(.turnStart, session: "old")
        rig.wait(25 * 3600 * 1000, every: 60_000)  // forgotten
        fx = rig.send(.turnEnd, session: "old")
        XCTAssertEqual(events(fx), [], "a session forgotten mid-turn")
        XCTAssertEqual(rig.state.base, "idle")
    }

    /// A session Boop first sees partway through a turn (it launched, or
    /// forgot the session, meanwhile) works from its first call, but Boop
    /// never saw the turn start, so it can't say how long it ran or what
    /// it did: its end tells the brain nothing, whether done, failed or
    /// stopped, as a stop already didn't, and nothing
    /// celebrates it. Before, it was "turn 0", timed
    /// from the first hook Boop saw.
    func testATurnBoopJoinedPartwayEndsWithoutAnEvent() {
        let rig = CoreRig()
        rig.send(.activity, tool: "Bash", failed: false)
        XCTAssertEqual(rig.state.base, "working")
        rig.wait(5000)
        rig.send(.activity, tool: "Read")
        rig.send(.activity, tool: "Read", failed: false)
        var fx = rig.send(.turnEnd)
        XCTAssertEqual(events(fx), [], "it just goes idle")
        XCTAssertEqual(rig.state.base, "idle")

        rig.send(.activity, session: "f", tool: "Bash")
        rig.wait(5000)
        fx = rig.send(.turnFailed, session: "f")
        XCTAssertEqual(events(fx), [], "failed")
        XCTAssertEqual(rig.state.base, "idle")

        rig.send(.turnStart, session: "f")
        XCTAssertEqual(woke(rig.send(.turnEnd, session: "f")), [#"claude finished turn 1 on "landing": done, a short turn, no tool calls."#],
                       "the next turn, which Boop saw start, is reported")
    }

    /// A turn the main agent's call opens with no prompt (Claude carrying
    /// on after another hook blocked its `Stop`) counts its own tool calls
    /// and topics, from that call: `tools` are the turn's.
    func testATurnACallOpensCountsItsOwnTools() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests", id: "t")
        rig.wait(20_000)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false, id: "t")
        XCTAssertEqual(woke(rig.send(.turnEnd)),
                       [#"claude finished turn 1 on "landing": done, a short turn, 1 tool call."#])
        rig.wait(1000)
        rig.send(.activity, tool: "Edit", id: "e")
        rig.wait(30_000)
        rig.send(.activity, tool: "Edit", failed: false, id: "e")
        let second = events(rig.send(.turnEnd))
        XCTAssertEqual(second.map(\.line), [#"claude finished turn 1 on "landing": done, a short turn, 1 tool call, the 2nd quick win of a streak."#],
                       "a second finish on the thread within 10 minutes")
        XCTAssertEqual(second.first?.facts["tools"], .int(1), "its own call only")
        XCTAssertEqual(second.first?.facts["topics"], .object([:]), "none of the last turn's topics")
        XCTAssertEqual(second.first?.facts["length_ms"], .int(30_000), "from that call")
        rig.wait(1000)
        XCTAssertEqual(events(rig.send(.turnEnd)), [], "no turn open")
    }

    /// Claude's idle notice means it has sat at its prompt
    /// for a minute, so one that lands less than 30 s after a turn started
    /// is from before it: you typed a new prompt just as the minute after
    /// an Esc ran out. It's ignored, and the new turn goes on working.
    func testAStaleIdleNoticeDoesntStopANewTurn() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(59_500)  // Esc on the prompt: no hook
        rig.send(.turnStart)
        rig.now += 10
        let fx = rig.send(.turnStopped, notice: true)
        XCTAssertEqual(events(fx), [])
        XCTAssertEqual(rig.state.base, "working")
        rig.wait(30_000)
        rig.send(.turnStopped, notice: true)  // no stale notice waits this long
        XCTAssertEqual(rig.state.base, "idle")

        rig.send(.turnStart, .codex, session: "c")
        rig.now += 10
        rig.send(.turnStopped, .codex, session: "c")  // Codex's Interrupt is never stale
        XCTAssertEqual(rig.state.base, "idle")

        // A turn a call started had no prompt to race: the main agent's
        // call 50 s after its Stop (another hook blocked it), and the idle
        // notice 10 s later, is a real one.
        rig.send(.turnStart, session: "d")
        rig.send(.turnEnd, session: "d")
        rig.wait(50_000)
        rig.send(.activity, session: "d", tool: "Read")
        XCTAssertEqual(rig.state.base, "working")
        rig.wait(10_000)
        XCTAssertEqual(finished(rig.send(.turnStopped, session: "d", notice: true)), ["stopped"], "the notice counts")
        XCTAssertEqual(rig.state.base, "idle")
    }

    /// Only the main agent's call
    /// opens a turn. A background helper that works on after the main
    /// agent's `Stop` shows working, and its results count, but it's no
    /// turn: no working heartbeat, and Claude's idle notice finishes
    /// nothing and plays no `stopped`. Its end, with no call left running,
    /// makes the session idle. Before, its first call opened a turn that
    /// its end left working, heartbeats and all, until the idle notice
    /// stopped that turn with a `stopped` nobody caused.
    func testABackgroundHelperIsNoTurn() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Task", id: "tk")
        rig.send(.subagentStart, subagent: "a1")
        rig.send(.activity, tool: "Task", failed: false, id: "tk")
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
        rig.wait(1000)
        rig.send(.activity, subagent: "a1", tool: "Bash", topic: "tests", id: "b")
        XCTAssertEqual(rig.state.base, "working")
        XCTAssertEqual(rig.state.act, "testing")
        XCTAssertEqual(workBeats(rig.wait(5 * 60_000)), [], "no working heartbeat")
        let failed = rig.send(.activity, subagent: "a1", tool: "Bash", topic: "tests", failed: true, id: "b")
        XCTAssertEqual(deviceReactions(failed).map(\.anim), ["error"], "its result isn't a late one")
        XCTAssertEqual(woke(failed), [#"claude's tests failed on "landing"."#])
        XCTAssertEqual(rig.state.base, "working")
        rig.send(.subagentEnd, subagent: "a1")
        XCTAssertEqual(rig.state.base, "idle", "the helper is done")
        rig.wait(60_000)
        let notice = rig.send(.turnStopped, notice: true)
        XCTAssertEqual(deviceReactions(notice), [], "nothing stopped")
        XCTAssertEqual(finished(notice), [])
    }

    /// A turn's outcome is its own last check. A
    /// background helper's tests that fail after the main agent's `Stop`
    /// aren't carried into the turn the main agent's next call opens with
    /// no prompt (another hook blocked its `Stop`), which ran none: that
    /// turn is done. Before, it finished failed.
    func testAHelpersCheckAfterStopIsntTheNextTurns() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Task", id: "tk")
        rig.send(.subagentStart, subagent: "a1")
        rig.send(.activity, tool: "Task", failed: false, id: "tk")
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
        rig.wait(1000)
        rig.send(.activity, subagent: "a1", tool: "Bash", topic: "tests", id: "b")
        rig.send(.activity, subagent: "a1", tool: "Bash", topic: "tests", failed: true, id: "b")
        rig.send(.subagentEnd, subagent: "a1")
        rig.wait(1000)
        rig.send(.activity, tool: "Edit", id: "e")
        rig.send(.activity, tool: "Edit", failed: false, id: "e")
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
    }

    /// Claude gives a subagent's hooks its parent's session, and the hooks
    /// that end, fail or start a turn say so with the subagent's
    /// `agent_id` when one sends them. They're that subagent's: they
    /// answer its own request, as its end does, and leave the session's
    /// turn and everyone else's requests alone.
    func testASubagentsTurnLevelHooksAreItsOwn() {
        for kind in [Hook.turnFailed, .turnEnd, .sessionStart, .turnStart, .sessionEnd] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.activity, tool: "Agent")
            rig.send(.needsYou, subagent: "A", tool: "Bash")
            let fx = rig.send(kind, subagent: "B")
            XCTAssertNotNil(rig.state.attn, "\(kind.rawValue): A's prompt is still up")
            XCTAssertEqual(events(fx), [], kind.rawValue)
            rig.send(kind, subagent: "A")
            XCTAssertNil(rig.state.attn, "\(kind.rawValue): A's own answers it")
            XCTAssertEqual(rig.sessions, [["claude", "landing", "working"]], "\(kind.rawValue): the turn goes on")
        }
    }

    func testFailedTurnPlaysNoReactionAndGoesIdle() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.wait(60_000)
        let fx = rig.send(.turnFailed)
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": failed, a long turn, no tool calls."#])
        XCTAssertNil(events(fx).first?.reaction, "the rules did nothing")
    }

    /// A turn whose last test, build or deploy command
    /// failed is a failed turn: no finish, and the brain hears it
    /// as failed.
    func testATurnThatLeavesItsTestsFailingFails() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.send(.activity, tool: "Edit", topic: "docs", failed: false)  // not a check
        rig.send(.activity, tool: "Read", failed: false)
        rig.send(.activity, tool: "Bash", topic: "tests")  // no result: PreToolUse, or Codex
        rig.wait(60_000)
        let fx = rig.send(.turnEnd)
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": failed, a long turn, 4 tool calls, after a failed check."#])
        XCTAssertEqual(events(fx).first?.facts["topics"], .object(["tests": "failing", "docs": "edited"]))
        XCTAssertEqual(events(fx).first?.facts["tools_failed"], .int(1))
    }

    func testATurnWhoseLastCheckPassedCheers() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "build", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false)
        rig.wait(60_000)
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
        // The next turn starts clean: a failure in the last one doesn't count.
        rig.wait(5000)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "deploy", failed: true)
        rig.send(.turnEnd)
        rig.wait(5000)
        rig.send(.turnStart)
        rig.wait(1000)
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
    }

    func testTheErrorClassReachesTheEvent() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.send(.activity, tool: "Read")
        rig.wait(3000)
        let fx = rig.send(.turnFailed, error: "rate_limit")
        let failed = events(fx).first
        XCTAssertEqual(failed?.line, #"claude finished turn 1 on "landing": failed, a short turn, no tool calls."#)
        XCTAssertEqual(failed?.facts["outcome"], "failed")
        XCTAssertEqual(failed?.facts["error"], "rate_limit")
    }
}

// MARK: - Something needs you

final class CoreNeedsYouTests: XCTestCase {
    func testClaudeNeedsYouShowsImmediately() {
        let rig = CoreRig()
        rig.send(.turnStart, project: "jetpack")
        let fx = rig.send(.needsYou, project: "jetpack", tool: "Bash")
        let attn = states(fx).last?.attn
        XCTAssertEqual(attn, StateSnapshot.Attention(agent: "claude", project: "jetpack", more: 0, id: 1))
        XCTAssertEqual(states(fx).last?.waiting, 1)
        XCTAssertEqual(rig.sessions, [["claude", "jetpack", "waiting"]])
        XCTAssertEqual(woke(fx), [], "needs you never wakes the brain")
        XCTAssertEqual(events(fx).map(\.line), [#"claude needs you on "jetpack"."#], "the brain hears of it")
    }

    /// Codex's request waits 2 s before it shows; in
    /// that grace the look is waiting.
    func testCodexWaitsTwoSeconds() {
        XCTAssertEqual(SessionTracker.codexGraceMs, 2000)
        let rig = CoreRig()
        rig.send(.turnStart, .codex)
        XCTAssertEqual(states(rig.send(.needsYou, .codex, tool: "shell")).map(\.visual), ["waiting"])
        XCTAssertNil(rig.state.attn)
        rig.wait(1000)
        XCTAssertNil(rig.state.attn)
        let fx = rig.wait(1000)
        XCTAssertEqual(states(fx).last?.attn?.agent, "codex")
    }

    func testCodexRequestHandledByItsReviewerNeverShows() {
        let rig = CoreRig()
        rig.send(.turnStart, .codex)
        rig.send(.needsYou, .codex, tool: "shell")
        rig.wait(1500)
        rig.send(.activity, .codex, tool: "shell")
        rig.wait(10_000)
        XCTAssertNil(rig.state.attn)
        XCTAssertTrue(rig.log.allSatisfy { if case .state(let s) = $0 { return s.attn == nil } else { return true } })
    }

    /// A Codex request shows on the tick after its grace.
    /// One the session's next event answers before that tick never showed,
    /// so it's never recorded as needing you either: no `needs_you` event
    /// for HISTORY, no `state` with `attn`. Another request from the
    /// session, which answers nothing, shows it then, dated 2 s after it
    /// arrived.
    func testACodexRequestAnsweredBeforeATickShowsItIsNeverRecorded() {
        for answer in [Hook.activity, .turnEnd, .turnStopped] {
            let rig = CoreRig()
            rig.send(.turnStart, .codex)
            rig.send(.needsYou, .codex, tool: "shell")
            rig.now += 2050  // past the grace, before the next tick
            let fx = rig.send(answer, .codex, tool: answer == .activity ? "shell" : nil)
            XCTAssertEqual(events(fx).filter { $0.name == "tool wait" }.map(\.line), [], "\(answer)")
            XCTAssertTrue(rig.log.allSatisfy { if case .state(let s) = $0 { return s.attn == nil } else { return true } },
                          "\(answer)")
        }
        let rig = CoreRig()
        rig.send(.turnStart, .codex, session: "a")
        rig.send(.needsYou, .codex, session: "a", tool: "shell")
        rig.now += 2500
        let fx = rig.send(.needsYou, .codex, session: "a", tool: "shell")
        XCTAssertEqual(states(fx).last?.attn?.agent, "codex")
        XCTAssertEqual(events(fx).map(\.line), [#"codex needs you on "landing"."#])
        rig.now += 100
        rig.send(.needsYou, session: "b", project: "jetpack", tool: "Bash")
        XCTAssertEqual(rig.state.attn?.project, "landing", "it has waited since 2 s after it arrived")
    }

    func testAnyLaterEventClearsIt() {
        for clearing in [Hook.activity, .turnStart, .turnEnd, .turnFailed, .sessionEnd, .sessionStart] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.needsYou, tool: "Bash")
            rig.wait(4000)
            let fx = rig.send(clearing)
            XCTAssertNil(states(fx).last?.attn, clearing.rawValue)
            XCTAssertNotNil(states(fx).last, clearing.rawValue)
        }
    }

    func testApprovingGoesBackToWork() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        XCTAssertEqual(rig.state.base, "idle")
        let fx = rig.send(.activity, tool: "Bash")
        XCTAssertEqual(states(fx).last?.base, "working")
    }

    /// Claude has no hook for the moment you approve, so a
    /// request clears only when the approved tool finishes. A long command
    /// keeps "needs you" up until then, and one that runs past the safety
    /// net leaves the session idle until it finishes.
    func testAnApprovedLongCommandKeepsNeedsYouUntilItFinishes() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")  // PreToolUse comes before the permission check
        rig.send(.needsYou, tool: "Bash")
        rig.send(.needsYou)  // its Notification
        rig.wait(120_000)  // approved at once; the tests take two minutes
        XCTAssertNotNil(rig.state.attn, "nothing says you approved")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", topic: "tests", failed: false)).last?.base, "working")
        XCTAssertNil(rig.state.attn)

        rig.send(.activity, tool: "Bash", topic: "build")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(SessionFold.safetyNetMs)
        XCTAssertNil(rig.state.attn, "the safety net")
        XCTAssertEqual(rig.state.base, "idle", "though the approved build still runs")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", topic: "build", failed: false)).last?.base, "working")
    }

    func testDuplicateWhileWaitingIsIgnored() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(3000)
        let fx = rig.send(.needsYou)  // the matching Notification
        XCTAssertEqual(states(fx), [])
        XCTAssertEqual(rig.state.attn?.more, 0)
    }

    func testALateNotificationAfterAQuickApprovalIsIgnored() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.send(.activity, tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou)  // Notification, no tool
        XCTAssertNil(rig.state.attn)
        rig.wait(10_000)
        rig.send(.needsYou, tool: "Bash")  // a real new request
        XCTAssertNotNil(rig.state.attn)
    }

    /// Claude gives a subagent's hooks its parent's session.
    /// A sibling's tool calls don't answer another agent's request; only the
    /// asker's own next event, or a turn-level one, does.
    func testASiblingSubagentsToolsDontAnswerTheRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn)
        rig.wait(500)
        rig.send(.activity, subagent: "a2", tool: "Read")
        rig.send(.activity, tool: "Agent")  // the main agent: another subagent came back
        XCTAssertNotNil(rig.state.attn, "a sibling kept working")
        rig.wait(5500)
        XCTAssertEqual(states(rig.send(.needsYou)), [], "its Notification is the same request")
        rig.wait(60_000)
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNotNil(rig.state.attn)
        let fx = rig.send(.activity, subagent: "a1", tool: "Bash")  // approved
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "working")
    }

    /// An agent can have calls running alongside the one
    /// that asks: Claude runs read-only calls in parallel, and the main
    /// agent's Agent call runs while it asks. The result of one of those,
    /// for another tool, isn't the asking call's answer; the asking call's
    /// own result, or the agent starting a new call, is. An `Elicitation`
    /// asks for no tool, so no result answers it: its `ElicitationResult`
    /// does, or the agent's next call.
    func testAParallelCallsResultDoesntAnswerTheRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "A", tool: "WebFetch", id: "a1")
        rig.send(.activity, subagent: "A", tool: "Grep", id: "a2")
        rig.send(.needsYou, subagent: "A", tool: "WebFetch")
        rig.send(.needsYou)
        rig.send(.activity, subagent: "A", tool: "Grep", failed: false, id: "a2")
        XCTAssertNotNil(rig.state.attn, "the Grep's result")
        rig.send(.activity, subagent: "A", tool: "WebFetch", failed: false, id: "a1")
        XCTAssertNil(rig.state.attn, "its own result")

        rig.send(.activity, tool: "Agent", id: "ta")
        rig.send(.activity, tool: "WebFetch", id: "tw")
        rig.send(.needsYou, tool: "WebFetch")
        rig.send(.activity, subagent: "B", tool: "Read", id: "b1")
        rig.send(.activity, subagent: "B", tool: "Read", failed: false, id: "b1")
        rig.send(.activity, tool: "Agent", failed: false, id: "ta")
        XCTAssertNotNil(rig.state.attn, "the Agent call's result")
        rig.send(.activity, tool: "Bash", id: "tb")
        XCTAssertNil(rig.state.attn, "a new call: it moved on")

        for answer in ["ElicitationResult", "next call"] {
            rig.send(.activity, subagent: "C", tool: "mcp__jira__create", id: "c1")
            rig.send(.activity, subagent: "C", tool: "Read", id: "c2")
            rig.send(.needsYou, subagent: "C", notice: false)  // the MCP tool's Elicitation
            rig.send(.activity, subagent: "C", tool: "Read", failed: false, id: "c2")
            XCTAssertNotNil(rig.state.attn, "\(answer): the parallel Read's result")
            rig.send(.activity, subagent: "C", tool: answer == "next call" ? "Grep" : nil, id: answer == "next call" ? "c3" : nil)
            XCTAssertNil(rig.state.attn, answer)
            rig.send(.activity, subagent: "C", tool: "mcp__jira__create", failed: false, id: "c1")
        }
    }

    /// Two subagents asking at once: "needs you" stays until both are
    /// answered, and a turn-level event answers everyone.
    func testEveryAskerMustBeAnswered() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a2", tool: "Edit")
        XCTAssertEqual(rig.state.attn?.more, 0, "one session")
        rig.send(.activity, subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn, "a2 still waits")
        rig.send(.activity, subagent: "a2", tool: "Edit")
        XCTAssertNil(rig.state.attn)
        for turnLevel in [Hook.turnEnd, .turnFailed, .sessionEnd] {
            rig.send(.turnStart)
            rig.send(.needsYou, subagent: "a1", tool: "Bash")
            rig.send(.activity, subagent: "a2", tool: "Read")
            XCTAssertNotNil(rig.state.attn, turnLevel.rawValue)
            rig.send(turnLevel)
            XCTAssertNil(rig.state.attn, turnLevel.rawValue)
        }
    }

    /// A Notification repeats the request its agent's own
    /// hook makes, so one with nothing waiting is the late copy of the
    /// request that last cleared if it comes within 5 s of the clear, or
    /// before any tool call has started since: a new request always follows
    /// a new call. Here the turn has ended and it comes 5.5 s late.
    func testALateNotificationAfterTheTurnEndedIsIgnored() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(500)
        rig.send(.activity, tool: "Bash", failed: false)  // approved
        rig.send(.turnEnd)
        rig.wait(5500)
        XCTAssertEqual(rig.send(.needsYou), [], "no call since the clear")
        XCTAssertNil(rig.state.attn)
        rig.wait(60_000)
        XCTAssertNil(rig.state.attn)

        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash")
        rig.wait(6000)
        rig.send(.needsYou)  // a request whose own hook never came
        XCTAssertNotNil(rig.state.attn, "a call started since the clear")
    }

    /// An `Elicitation` is a request of its own, never a late
    /// copy, however soon after a clear it comes: approved, then an MCP
    /// tool asks you something; or Esc, the idle notice, a new prompt and
    /// the MCP tool at once.
    func testAnElicitationRightAfterAClearShows() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(300)
        rig.send(.activity, tool: "Bash", failed: false)
        rig.now += 500
        rig.send(.activity, tool: "mcp__jira__create")
        rig.now += 500
        let fx = rig.send(.needsYou, notice: false)
        XCTAssertNotNil(states(fx).last?.attn)
        XCTAssertEqual(events(fx).map(\.line), [#"claude needs you on "landing"."#])
        XCTAssertEqual(states(rig.send(.needsYou)), [], "its Notification is the same request")
        rig.send(.activity)  // ElicitationResult
        XCTAssertNil(rig.state.attn)

        rig.now += 1000
        XCTAssertEqual(rig.send(.needsYou, kind: "elicitation_dialog"), [], "the Elicitation's own, late")

        rig.send(.needsYou, tool: "Bash")
        rig.wait(60_000)
        rig.send(.turnStopped)  // Esc on it; Claude's idle notice
        rig.send(.turnStart)
        rig.send(.activity, tool: "mcp__srv__deploy")
        XCTAssertNotNil(states(rig.send(.needsYou, notice: false)).last?.attn)

        // A dialog's Notification whose own hook was lost isn't taken for
        // a permission prompt's copy: only a late copy of the same kind is.
        rig.send(.activity)
        rig.send(.activity, tool: "Bash")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(500)
        rig.send(.activity, tool: "Bash", failed: false)
        rig.now += 1500
        XCTAssertNotNil(states(rig.send(.needsYou, kind: "elicitation_dialog")).last?.attn)
    }

    /// A Notification that lands before its own request's
    /// hook starts a request from "anyone"; the hook, which names who asked,
    /// then takes it over, so a sibling's tool call doesn't answer it.
    func testANotificationBeforeItsRequestBecomesThatRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou)  // the Notification, first
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNotNil(rig.state.attn, "a sibling's call")
        rig.send(.activity, subagent: "a1", tool: "Bash", failed: false)
        XCTAssertNil(rig.state.attn)
    }

    /// An `Elicitation` names who asked, as a tool request
    /// does, so it's answered by that agent's next event or a turn-level
    /// one: a sibling's call doesn't hide the dialog, answering it doesn't
    /// hide a sibling's prompt, and one that comes while a sibling's request
    /// waits joins it.
    func testASubagentsElicitationIsItsOwn() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "b", tool: "mcp__x__ask")
        rig.send(.needsYou, subagent: "b", notice: false)
        rig.send(.activity, subagent: "a", tool: "Read")
        XCTAssertNotNil(rig.state.attn, "b's dialog is still up")
        rig.send(.activity, subagent: "b")  // ElicitationResult
        XCTAssertNil(rig.state.attn)

        rig.send(.needsYou, subagent: "a", tool: "Bash")
        rig.send(.needsYou, subagent: "b", notice: false)
        rig.send(.activity, subagent: "b")
        XCTAssertNotNil(rig.state.attn, "a's prompt is still up")
        rig.send(.needsYou, subagent: "b", notice: false)
        rig.send(.activity, subagent: "a", tool: "Bash", failed: false)
        XCTAssertNotNil(rig.state.attn, "b's dialog is still up")
        rig.send(.activity, subagent: "b")
        XCTAssertNil(rig.state.attn)
    }

    /// A request that came as a Notification alone doesn't
    /// say who asked, so any event from the session answers it, as before
    /// subagents; but a call answers it only from its second second on.
    /// Before, a sibling's call landing between a Notification and its own
    /// hook answered it, and the hook showed it again: amber flickered, and
    /// the device announced one prompt twice.
    func testANotificationAloneIsAnsweredByAnyEventButNotACallAtOnce() {
        XCTAssertEqual(SessionTracker.noticeFirstMs, 1000)
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Bash")
        var fx = rig.send(.needsYou)
        rig.now += 300
        fx += rig.send(.activity, subagent: "a2", tool: "Read")
        rig.now += 300
        fx += rig.send(.needsYou, subagent: "a1", tool: "Bash")
        let needs = fx.effects.compactMap { effect -> Event? in
            guard case .record(let e) = effect, e.specificType == Core.needsYou else { return nil }
            return e
        }
        XCTAssertEqual(needs.map(\.phase), [.start], "one request, whose own hook took it over")

        rig.send(.activity, subagent: "a1", tool: "Bash", failed: false)
        rig.send(.turnEnd)
        rig.wait(6000)
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou)  // its own hook never comes
        XCTAssertNotNil(rig.state.attn)
        rig.now += SessionTracker.noticeFirstMs - 1
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNotNil(rig.state.attn, "its own hook may still come")
        rig.now += 1
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNil(rig.state.attn)
    }

    /// A subagent you deny carries on, and one that then
    /// ends without another tool call sends only `SubagentStop`. Its end
    /// answers its own request and nobody else's, and the main agent's turn
    /// goes on working. The brain hears only that you answered.
    func testASubagentsEndAnswersOnlyItsOwnRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent")
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a2", tool: "Edit")
        rig.wait(20_000)  // both denied: no hook says so
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a3")), [], "a sibling's end")
        XCTAssertEqual(states(rig.send(.subagentEnd)), [], "an end that names no subagent")
        let first = rig.state.attn?.id
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a1")).count, 1, "a2's prompt is shown now")
        XCTAssertNotNil(rig.state.attn, "a2 still waits")
        XCTAssertNotEqual(rig.state.attn?.id, first)
        let fx = rig.send(.subagentEnd, subagent: "a2")
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "working", "the main agent's turn goes on")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "working"]])
        XCTAssertEqual(events(fx).map(\.line), [#"You answered claude on "landing"."#], "you denied it, and nothing else")
        rig.send(.activity, tool: "Agent", failed: false)
        XCTAssertEqual(finished(rig.send(.turnEnd)), ["done"])
    }

    /// It answers nobody else: not the main agent, and not a request that
    /// came as a Notification alone, which doesn't say who asked (a1's own
    /// hook comes more than 5 s later, so it's another request). The end of
    /// a subagent that never asked leaves either one up.
    func testASubagentsEndLeavesOtherAskersWaiting() {
        for asker in ["main agent", "notification alone"] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.needsYou, tool: asker == "main agent" ? "Bash" : nil)
            let shown = rig.state.attn
            XCTAssertNotNil(shown, asker)
            XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a2")), [], "\(asker): a2 never asked")
            XCTAssertEqual(rig.state.attn, shown, asker)
            rig.wait(6000)
            rig.send(.needsYou, subagent: "a1", tool: "Bash")
            rig.send(.subagentEnd, subagent: "a1")
            XCTAssertNotNil(rig.state.attn, asker)
            rig.send(.activity, tool: "Bash")
            XCTAssertNil(rig.state.attn, asker)
        }
    }

    /// A subagent's end isn't activity. One that comes
    /// after its session's turn has ended (a background subagent finishing
    /// late) leaves the session idle, one from a session Boop hasn't seen
    /// creates it idle, and a turn gone stale stays stale. A request that
    /// came while no turn was going leaves the session idle when it clears.
    func testASubagentsEndNeverMakesASessionWork() {
        let rig = CoreRig(rules: .chatty)
        rig.turn(5000)
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a1")), [])
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(workBeats(rig.wait(10 * 60_000)), [], "no working heartbeat")

        rig.send(.subagentEnd, session: "s2", subagent: "a1")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"], ["claude", "landing", "idle"]])

        rig.send(.turnStart, session: "s3")
        rig.wait(SessionFold.staleWorkMs)
        XCTAssertEqual(rig.state.base, "idle", "an hour without events")
        XCTAssertEqual(states(rig.send(.subagentEnd, session: "s3", subagent: "a1")), [])
        XCTAssertEqual(rig.state.base, "idle", "still stale")

        rig.send(.needsYou, session: "s4", subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn)
        let fx = rig.send(.subagentEnd, session: "s4", subagent: "a1")
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "idle", "no turn was going")
    }

    /// The strip names where the request was made.
    /// While it waits, a sibling subagent's calls from another folder don't
    /// move the session's project, so the strip doesn't flip between them,
    /// and no new `state` goes out for a request that hasn't changed.
    func testAWaitingSessionKeepsItsProject() {
        let rig = CoreRig()
        rig.send(.turnStart, project: "alpha")
        rig.send(.needsYou, subagent: "a1", project: "alpha", tool: "Bash")
        var fx = Fx()
        for p in ["web", "alpha", "web"] { fx += rig.send(.activity, subagent: "a2", project: p, tool: "Bash") }
        XCTAssertEqual(states(fx), [])
        XCTAssertEqual(rig.state.attn?.project, "alpha")
        XCTAssertEqual(rig.sessions, [["claude", "alpha", "waiting"]])
        rig.send(.activity, subagent: "a1", project: "alpha", tool: "Bash")  // approved
        rig.send(.activity, subagent: "a2", project: "web", tool: "Bash")
        XCTAssertEqual(rig.sessions, [["claude", "web", "working"]], "then it follows its events again")
    }

    /// The sign shows the thread's name
    /// in the project's place, cut to the sign's 47 bytes. The session keeps
    /// the last name an event brought, and one with none sends no `name`.
    func testTheStripNamesTheThreadThatAsks() {
        let rig = CoreRig()
        var ask = rig.event(.needsYou, project: "landing", tool: "Bash")
        ask.data["name"] = "Thread name on \"needs you\" screen, with a sign on it"
        rig.send(ask)
        XCTAssertEqual(rig.state.attn?.name, "Thread name on \"needs you\" screen, with a sig..")
        XCTAssertTrue(rig.state.jsonLine.contains(#""project":"landing","name":"Thread name on \"needs you\" screen, with a sig..","more":0"#))
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.name, "Thread name on \"needs you\" screen, with a sign on it",
                       "the popover shows it whole")
        rig.send(.activity, tool: "Bash")  // approved
        rig.send(.needsYou, tool: "Edit")  // a request that brings no name
        XCTAssertEqual(rig.state.attn?.name, "Thread name on \"needs you\" screen, with a sig..", "the session keeps it")
        rig.send(.needsYou, session: "s2", project: "jetpack", tool: "Bash")
        rig.send(.activity)  // s1 answered: s2 is shown
        XCTAssertEqual(rig.state.attn?.project, "jetpack")
        XCTAssertEqual(rig.state.attn?.name, "")
        XCTAssertFalse(rig.state.jsonLine.contains("\"name\""))
    }

    /// Every event can bring the thread's name, so the
    /// popover and a cheer name a thread before it ever asks, and follow a
    /// rename at its next event.
    func testAThreadIsNamedBeforeItAsks() {
        let rig = CoreRig()
        var prompt = rig.event(.turnStart, project: "landing")
        prompt.data["name"] = "Fix the nav"
        rig.send(prompt)
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.name, "Fix the nav")
        XCTAssertEqual(rig.view.who(about: SessionFold.key(.claude, "s1"), rig.pipeline.transcript.view(now: rig.now))?.thread,
                       "Fix the nav", "a cheer names it")
        rig.send(.activity, tool: "Bash")  // an event with no name keeps it
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.name, "Fix the nav")
        var renamed = rig.event(.activity, tool: "Edit")
        renamed.data["name"] = "Nav bar fix"
        rig.send(renamed)
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.name, "Nav bar fix")
    }

    func testMoreThanOneShowsTheOldestWithACount() {
        let rig = CoreRig()
        rig.send(.needsYou, .claude, session: "a", project: "jetpack", tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou, .claude, session: "b", project: "landing", tool: "Edit")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "jetpack", more: 1, id: 1))
        rig.send(.activity, session: "a")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "landing", more: 0, id: 2))
    }

    /// "a different request becomes the one shown: one
    /// more chirp". The device can only tell by `attn.id`, the request's
    /// number: two worktrees of one repo have the same
    /// agent and project. The number stays while more requests come and go
    /// behind it, and a new one is shown when the first is answered.
    func testTheRequestShownHasItsOwnNumber() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.send(.needsYou, session: "a", tool: "Bash")
        let first = rig.state.attn?.id
        rig.wait(400)
        rig.send(.needsYou, session: "b", tool: "Bash")
        XCTAssertEqual(rig.state.attn?.more, 1)
        XCTAssertEqual(rig.state.attn?.id, first, "still a's")
        rig.wait(400)
        rig.send(.activity, session: "a", tool: "Bash", failed: false)
        XCTAssertEqual(rig.state.attn?.project, "landing")
        XCTAssertNotEqual(rig.state.attn?.id, first, "b's is shown now")
        XCTAssertEqual(rig.state.attn?.more, 0)
    }

    /// The same inside one session: when one of two subagents asking is
    /// answered, the other's prompt is the one Claude shows, so it's a
    /// different request. A sibling asking too, or the hook of a request
    /// its Notification started, isn't.
    func testASecondAskerAnsweredShowsAnotherRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        let first = rig.state.attn?.id
        rig.send(.needsYou)  // its Notification
        rig.send(.needsYou, subagent: "a2", tool: "Edit")
        XCTAssertEqual(rig.state.attn?.id, first)
        rig.send(.activity, subagent: "a1", tool: "Bash", failed: false)
        XCTAssertNotNil(rig.state.attn)
        XCTAssertNotEqual(rig.state.attn?.id, first)

        rig.send(.turnEnd)
        rig.wait(6000)
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a3", tool: "Bash")
        rig.send(.needsYou)  // a Notification first
        let second = rig.state.attn?.id
        XCTAssertNotNil(second)
        rig.send(.needsYou, subagent: "a3", tool: "Bash")
        XCTAssertEqual(rig.state.attn?.id, second, "its own hook")
    }

    /// `attn` names the session that has waited longest.
    /// Two requests in the same millisecond keep the order they arrived
    /// in, not the order the sessions were first seen.
    func testRequestsInTheSameMillisecondKeepTheirOrder() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "s1", project: "jetpack")
        rig.send(.turnStart, session: "s2", project: "landing")
        rig.send(.needsYou, session: "s2", project: "landing", tool: "Bash")
        let first = rig.state.attn
        let fx = rig.send(.needsYou, session: "s1", project: "jetpack", tool: "Bash")
        XCTAssertEqual(states(fx).map { $0.attn?.project }, ["landing"])
        XCTAssertEqual(rig.state.attn?.id, first?.id)
        XCTAssertEqual(rig.state.attn?.more, 1)
        XCTAssertEqual(rig.sessions.map { $0[1] }, ["landing", "jetpack"])
    }

    /// After 10 minutes with no events "needs you" clears,
    /// and the session goes idle rather than back to working: no sweat drop
    /// and no working heartbeat while the agent may still be waiting on its prompt.
    func testSafetyNetClearsAfterTenQuietMinutes() {
        XCTAssertEqual(SessionFold.safetyNetMs, 600_000)
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(599_000)
        XCTAssertNotNil(rig.state.attn)
        rig.wait(1000)
        XCTAssertNil(rig.state.attn)
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(workBeats(rig.wait(600_000)), [], "no working heartbeat")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash")).last?.base, "working", "until the agent acts again")
    }

    /// The safety net also covers a Codex request no tick
    /// saw through its 2 s grace, as when the Mac sleeps right after Codex
    /// asks: the session goes idle rather than staying at work.
    func testSafetyNetCoversACodexRequestStillInItsGrace() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart, .codex)
        rig.send(.activity, .codex, tool: "shell", topic: "deploy")
        rig.send(.needsYou, .codex, tool: "shell")
        rig.now += SessionFold.safetyNetMs  // one tick, on waking
        let fx = rig.note(Fx(rig.pipeline.tick(at: rig.now)))
        XCTAssertEqual(states(fx).last?.base, "idle")
        XCTAssertNil(rig.state.attn)
        XCTAssertEqual(events(fx), [], "it never showed")
        XCTAssertEqual(rig.sessions, [["codex", "landing", "idle"]])
        XCTAssertEqual(workBeats(rig.wait(600_000)), [], "no working heartbeat")
    }

    func testWhileSomethingNeedsYouNothingWakesTheBrain() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(5000)
        rig.send(.needsYou, session: "a", tool: "Bash")
        rig.wait(60_000)
        let ended = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(woke(ended), [])
        XCTAssertEqual(events(ended).count, 1, "it still comes, for HISTORY")
    }

    /// An event that answers the last asker clears the
    /// request before it applies, so the event it makes is judged with
    /// nothing needing you, whichever kind it is:
    /// tests that fail right after you approved them, the turn Claude's
    /// idle notice stops after Esc on its prompt, and Codex's `Interrupt`.
    func testAnEventThatAnswersTheRequestWakesTheBrain() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(2000)
        XCTAssertEqual(woke(rig.send(.activity, tool: "Bash", topic: "tests", failed: true)),
                       [#"claude's tests failed on "landing"."#])

        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(61_000)
        XCTAssertEqual(woke(rig.send(.turnStopped)).count, 1, "the stopped turn")

        rig.send(.turnStart, .codex, session: "c")
        rig.send(.needsYou, .codex, session: "c", tool: "shell")
        rig.wait(3000)
        XCTAssertNotNil(rig.state.attn)
        XCTAssertEqual(woke(rig.send(.turnStopped, .codex, session: "c")).count, 1, "Codex's Interrupt")
        XCTAssertNil(rig.state.attn)
    }

    /// Attention wins, so a turn
    /// that finishes while something needs you is recorded but wakes no
    /// brain, and nothing celebrates it. A turn whose `Stop` answers its
    /// own request reaches the brain, since nothing needs you by then.
    func testAFinishWhileSomethingNeedsYouWakesNothing() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a", project: "jetpack")
        rig.send(.turnStart, session: "b")
        rig.wait(3000)
        rig.send(.needsYou, session: "a", project: "jetpack", tool: "Bash")
        let fx = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(events(fx).map { $0.facts["outcome"] }, ["done"])
        XCTAssertEqual(finished(fx), [], "recorded, but the brain isn't woken")
        rig.send(.activity, session: "a", project: "jetpack", tool: "Bash")  // approved
        let next = rig.send(.turnEnd, session: "a", project: "jetpack")
        XCTAssertEqual(finished(next), ["done"], "nothing needs you now")

        rig.send(.turnStart, session: "b")
        rig.send(.needsYou, session: "b", tool: "Bash")
        let own = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(finished(own), ["done"], "its own Stop answered its request first")
    }
}

// MARK: - You and Boop

final class CoreYouAndBoopTests: XCTestCase {

    /// BOOT is the Mac's to judge: with nobody in line a press is a poke,
    /// and with an agent idle it opens that agent.
    func testAPressOpensTheNextOneOrPokes() {
        let rig = CoreRig()
        let alone = rig.note(Fx(rig.pipeline.press(at: rig.now)))
        XCTAssertEqual(opened(alone), [])
        XCTAssertEqual(rig.ruleActions, ["wiggle"], "nobody in line: a poke")
        rig.wait(5000)
        rig.send(.turnStart)
        rig.send(.turnEnd)
        rig.wait(1000)
        let before = rig.ruleActions
        XCTAssertEqual(opened(rig.note(Fx(rig.pipeline.press(at: rig.now)))).count, 1, "the idle agent opens")
        XCTAssertEqual(rig.ruleActions, before, "and no poke")
    }

    /// Face down is do not disturb until it's turned back up: nothing
    /// wakes the brain in between, and turning it up does.
    func testFaceDownHoldsTheBrainUntilItsTurnedUp() {
        let rig = CoreRig()
        rig.send(.turnStart)
        XCTAssertEqual(woke(rig.note(Fx(rig.pipeline.gesture("facedown", at: rig.now)))), [])
        rig.wait(60_000)
        XCTAssertEqual(woke(rig.send(.turnEnd)), [], "a finished turn while it lies face down")
        XCTAssertEqual(woke(rig.poke()), [])
        rig.wait(5000)
        XCTAssertEqual(woke(rig.note(Fx(rig.pipeline.gesture("peekaboo", at: rig.now)))).count, 1)
        rig.wait(5000)
        rig.send(.turnStart)
        rig.wait(60_000)
        XCTAssertEqual(woke(rig.send(.turnEnd)).count, 1, "face up again")
    }

    /// A poke is the rules' alone to react to: they
    /// record the device's wiggle as an action under it, and the brain
    /// hears of it. While something needs you, the device only squashes,
    /// and the tap opens the thread instead: no wiggle, and the brain
    /// isn't woken.
    func testAPokeWigglesByRuleAndReachesTheBrain() {
        let rig = CoreRig()
        let fx = rig.poke()
        XCTAssertEqual(woke(fx), ["You poked \(creature) while it slept."], "no session is open")
        XCTAssertEqual(rig.ruleActions, ["wiggle"])
        XCTAssertEqual(states(fx), [], "the rules add no reaction: the device has already wiggled")
        XCTAssertEqual(opened(fx), [])
        rig.wait(5000)
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        let needed = rig.poke()
        XCTAssertEqual(woke(needed), [], "the tap opens the thread; it doesn't wake the brain")
        XCTAssertEqual(rig.ruleActions, ["wiggle", "starting", "needs_you start", "open_thread"], "no wiggle")
    }

    /// A tap while something needs you opens the thread
    /// the sign names, the one that has waited longest, in the app it runs
    /// in, as the last event said.
    func testATapWhileSomethingNeedsYouOpensTheOldestWaitingThread() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a", app: "com.mitchellh.ghostty")
        rig.send(.turnStart, session: "b", app: "com.anthropic.claudefordesktop", appSession: "local_b")
        rig.send(.needsYou, session: "b", tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou, session: "a", tool: "Edit")
        XCTAssertEqual(opened(rig.poke()), [ThreadRef(agent: "claude", session: "b", app: "com.anthropic.claudefordesktop",
                                                      appSession: "local_b")])
        rig.send(.activity, session: "b", tool: "Bash", done: true)
        XCTAssertEqual(opened(rig.poke()), [ThreadRef(agent: "claude", session: "a", app: "com.mitchellh.ghostty")],
                       "b was answered: a is next")
        rig.send(.activity, session: "a", tool: "Edit", done: true)
        let after = rig.poke()
        XCTAssertEqual(opened(after), [], "nothing waits: a poke")
        XCTAssertEqual(rig.ruleActions.suffix(3), ["open_thread", "needs_you end", "wiggle"])
    }

    /// An agent event is recorded without the name,
    /// app, app session and mode its session already has, which the core
    /// carries on, so the transcript doesn't repeat them on every line. The
    /// first event of a session the core doesn't hold (after a launch, its
    /// end, or a day's silence it forgets, even with no tick between, as
    /// when the Mac slept) carries them all, so a tap still opens the
    /// thread in its app, and so does a session's first event each day.
    func testTheTranscriptLeavesOutWhatTheSessionAlreadyHas() {
        let rig = CoreRig()
        let constants = ["name", "app", "app_session", "mode"]
        func recorded(_ kind: Hook, tool: String? = nil, done: Bool? = nil, mode: String = "plan") -> [String] {
            var event = rig.event(kind, tool: tool, done: done, mode: mode, app: "com.anthropic.claudefordesktop",
                                  appSession: "local_s1")
            event.data["name"] = "Fix the nav"
            rig.send(event)
            let data = rig.pipeline.transcript.events.last { $0.from == .claude }!.data
            return constants.filter { data[$0] != nil }
        }
        XCTAssertEqual(recorded(.turnStart), constants, "a session the core doesn't hold yet")
        XCTAssertEqual(recorded(.activity, tool: "Bash"), [], "nothing changed")
        XCTAssertEqual(recorded(.activity, tool: "Bash", done: true, mode: "default"), ["mode"], "out of plan mode")
        XCTAssertEqual(recorded(.activity, tool: "Edit", mode: "acceptEdits"), [], "still not plan mode")
        XCTAssertEqual(rig.core.sessions["claude/s1"]?.name, "Fix the nav")
        rig.now += 10 * 3600 * 1000  // midnight
        XCTAssertEqual(recorded(.activity, tool: "Edit", done: true, mode: "default"), constants, "the day's first")
        XCTAssertEqual(recorded(.activity, tool: "Edit", mode: "default"), [])
        rig.now += SessionFold.forgetMs
        XCTAssertEqual(recorded(.needsYou, tool: "Bash"), constants, "the core forgets it before this event")
        XCTAssertEqual(opened(rig.poke()), [ThreadRef(agent: "claude", session: "s1", app: "com.anthropic.claudefordesktop",
                                                      appSession: "local_s1")])
        XCTAssertEqual(recorded(.sessionEnd), [])
        XCTAssertEqual(recorded(.sessionStart), constants, "a new session")
    }

    /// While `listening` shows, a tap only dips the face, even while
    /// something needs you: nothing opens.
    func testATapWhileListeningOpensNothing() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.talk(true)
        XCTAssertEqual(opened(rig.poke()), [])
    }

    /// Holding BOOT turns the Mac's mic on, and letting
    /// go turns it off; it's never on longer than 30 s. Once it's off, the
    /// device holds `listening` for the reply, 8 s at most. While the mic
    /// is on no mumble plays, and while `listening` shows a poke doesn't
    /// wiggle. The app's button works the same, but a dropped link stops
    /// only the device's.
    func testPushToTalk() {
        let rig = CoreRig()
        XCTAssertEqual(Core.listenLimitMs, 30_000)
        XCTAssertEqual(Core.replyWaitMs, 8000)
        XCTAssertTrue(rig.talk(true).contains(.listen(true, by: .device)))
        XCTAssertEqual(rig.core.reactionBlock, "the mic is on")
        XCTAssertEqual(rig.talk(true), Fx(), "already on")
        rig.poke()
        XCTAssertEqual(rig.ruleActions, [], "no wiggle while listening")
        XCTAssertFalse(rig.wait(29_000).contains(where: { if case .listen = $0 { true } else { false } }))
        XCTAssertTrue(rig.wait(1000).contains(.listen(false, by: .device)), "off at 30 s")
        XCTAssertNil(rig.core.reactionBlock)
        XCTAssertTrue(rig.core.showsListening(at: rig.now), "held for the reply")
        XCTAssertEqual(rig.talk(false), Fx(), "the release after the limit does nothing")
        rig.wait(8000)
        XCTAssertFalse(rig.core.showsListening(at: rig.now), "8 s at most")
        rig.poke()
        XCTAssertEqual(rig.ruleActions, ["wiggle"])

        rig.talk(true)
        rig.wait(2000)
        XCTAssertTrue(rig.talk(false).contains(.listen(false, by: .device)))
        rig.passed(reacted: true)
        XCTAssertFalse(rig.core.showsListening(at: rig.now), "the reply went out")

        let app = rig.core.listen(true, at: rig.now)
        XCTAssertTrue(app.contains(.listen(true, by: .app)))
        XCTAssertEqual(deviceReactions(app).map(\.name), ["listening"], "the device is told to show it")
        XCTAssertEqual(BoopDevice.play(BoopDevice.listening), .now, "at once")
        XCTAssertEqual(BoopDevice.play(BoopDevice.stopListening), .ifFree)
        XCTAssertFalse(rig.core.linkDown(at: rig.now).contains(.listen(false, by: .app)), "the app's button carries on")
        XCTAssertTrue(rig.core.listen(false, at: rig.now).contains(.listen(false, by: .app)))
        rig.talk(true)
        XCTAssertTrue(rig.core.linkDown(at: rig.now).contains(.listen(false, by: .device)), "its release can't arrive")
    }

    /// Every step of push-to-talk is the core's, and each is recorded by
    /// rule for whose button it was: the mic on (`listen_start`), off with
    /// the reply still to come and why (`listen_wait`), and `listening` over
    /// and why (`listen_end`). They make no line, so the brain hears none
    /// of them. `stop_listening` goes out where no reply is coming; a
    /// reaction is the reply, which the device ends `listening` for itself.
    func testPushToTalkIsRecorded() throws {
        let rig = CoreRig()
        func listens() -> [String] {
            rig.pipeline.transcript.events.filter { $0.type == .listen }.map {
                [$0.kind, $0.specificType, $0["why"]?.string].compactMap { $0 }.joined(separator: " ")
            }
        }
        func run(_ fx: [CoreEffect]) -> Fx { rig.note(Fx(rig.pipeline.effects(fx, at: rig.now))) }
        func stops(_ fx: Fx) -> Bool { deviceReactions(fx).map(\.name) == [BoopDevice.stopListening] }

        XCTAssertEqual(rig.talk(true).views, [], "no line")
        XCTAssertTrue(rig.pipeline.transcript.events.filter { $0.type == .listen }.allSatisfy { $0["by"] == "rule" })
        rig.talk(false)
        let said = rig.said("are the tests passing?")
        let seq = try XCTUnwrap(said.views.first?.seq)
        XCTAssertFalse(stops(run(rig.core.heard(replyTo: seq, at: rig.now))), "the reply may come")
        XCTAssertFalse(stops(rig.passed(about: seq - 1, reacted: false)), "a pass on something older")
        XCTAssertTrue(stops(rig.passed(about: seq, reacted: false)), "no reply")
        XCTAssertEqual(listens(), ["listen_start device", "listen_wait device released", "listen_end device no reply"])

        run(rig.core.listen(true, by: .app, at: rig.now))
        rig.wait(Core.listenLimitMs)
        XCTAssertFalse(stops(rig.passed(reacted: true)), "a reaction is the reply")
        XCTAssertEqual(listens().suffix(3), ["listen_start app", "listen_wait app limit", "listen_end app replied"])

        rig.talk(true)
        XCTAssertTrue(stops(run(rig.core.micFailed("no mic", at: rig.now))))
        XCTAssertEqual(rig.core.talk.trouble, "no mic")
        XCTAssertEqual(rig.pipeline.transcript.events.last { $0.type == .listen }?["trouble"], "no mic")
        rig.talk(true)
        XCTAssertNil(rig.core.talk.trouble, "until the next try")
        run(rig.core.linkDown(at: rig.now))
        rig.wait(Core.replyWaitMs)
        XCTAssertFalse(rig.core.showsListening(at: rig.now))
        XCTAssertEqual(listens().suffix(5), ["listen_start device", "listen_end device mic failed", "listen_start device",
                                             "listen_wait device link down", "listen_end device timed out"])
        XCTAssertTrue(stops(run(rig.core.heardNothing(at: rig.now))), "stop_listening ends nothing else")
        XCTAssertEqual(listens().count, 11, "nothing more to record")
        XCTAssertTrue(stops(run(rig.core.heard(replyTo: nil, at: rig.now))), "nothing to wake: no reply")
        XCTAssertEqual(listens().count, 11)
    }

    /// Every poke wakes the brain, with no limit; the
    /// line counts the ones in a row, each within 3 s of the last.
    func testPokesInARow() {
        let rig = CoreRig()
        rig.send(.sessionStart)  // awake: with no session, a run's first poke finds Boop asleep
        var lines: [String] = []
        for _ in 0..<4 {
            lines += woke(rig.poke())
            rig.wait(900)
        }
        XCTAssertEqual(lines, ["You poked \(creature).", "You poked \(creature) 2 times in a row.", "You poked \(creature) 3 times in a row.",
                               "You poked \(creature) 4 times in a row."])
        rig.wait(2100)
        XCTAssertEqual(woke(rig.poke()), ["You poked \(creature) again."], "3 s after the last: a new run, within 2 minutes of the last")
        var fx = Fx()
        for _ in 0..<20 { fx += rig.poke() }
        XCTAssertEqual(woke(fx).count, 20, "no limit")
    }

    /// The first activity of a new day is a new day, with no reaction: the
    /// morning stretch and yawn were removed.
    func testFirstActivityOfTheDayStartsTheDayQuietly() {
        let rig = CoreRig(newDay: true)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-14")))
        XCTAssertFalse(rig.send(.turnStart).contains { if case .newDay = $0 { true } else { false } }, "only the first activity")
    }

    /// Timers run on the steady time the core is
    /// given, and days and times of day on the wall clock the app reports.
    /// Setting the Mac's clock back an hour doesn't stretch the working
    /// heartbeat's wait; moving it past midnight starts a new day.
    func testTimersFollowTheSteadyClockAndDaysTheWallClock() {
        let rig = CoreRig(seed: 7, rules: .chatty)
        rig.send(.turnStart)
        rig.wait(1000)
        rig.core.setWallClock(rig.now - 3_600_000, at: rig.now)  // the Mac's clock set back an hour
        XCTAssertFalse(workBeats(rig.wait(120_000)).isEmpty, "the working heartbeat, on time")
        rig.core.setWallClock(rig.now + CoreRig.day, at: rig.now)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-15")))
    }

    /// The runtime's steady clock starts at the wall clock's time and never
    /// goes back.
    func testTheSteadyClockStartsAtTheWallClockAndNeverStepsBack() {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let clock = Runtime.steadyClock()
        var last = clock()
        XCTAssertLessThan(abs(last - wall), 100)
        for _ in 0..<1000 {
            let now = clock()
            XCTAssertGreaterThanOrEqual(now, last)
            last = now
        }
    }

    /// A new day is only the effect the runtime prunes the transcript on;
    /// nothing about it reaches the brain (the reflection was removed on
    /// 2026-09-26).
    func testANewDayReachesNoBrain() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.wait(24 * 3600 * 1000, every: 60_000)
        let fx = rig.send(.turnStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-15")))
        XCTAssertEqual(events(fx).map(\.name), ["turn start"])
    }
}

// MARK: - Personalities

final class CorePersonalityTests: XCTestCase {
    /// The gaps between working heartbeats over two working hours.
    func beatGaps(_ rig: CoreRig) -> [Int64] {
        rig.send(.turnStart)
        var times: [Int64] = []
        for _ in 0..<7200 {
            if !workBeats(rig.wait(1000)).isEmpty { times.append(rig.now) }
            rig.send(.activity)  // keep it working
        }
        return zip(times, times.dropFirst()).map { $1 - $0 }
    }

    /// The working heartbeat keeps the
    /// personality's pace, or never comes.
    func testTheWorkingHeartbeatKeepsThePersonalitysPace() {
        let fast = beatGaps(CoreRig(seed: 7, rules: Personality.Rules(workBeatMs: 30_000...60_000)))
        XCTAssertGreaterThan(fast.count, 100)
        for gap in fast { XCTAssertTrue((30_000...61_000).contains(gap), "\(gap)") }
        let usual = beatGaps(CoreRig(seed: 7))
        XCTAssertGreaterThan(usual.count, 25)
        for gap in usual { XCTAssertTrue((90_000...181_000).contains(gap), "\(gap)") }
        XCTAssertEqual(beatGaps(CoreRig(seed: 7, rules: Personality.Rules(workBeatMs: nil))), [])
    }

    /// The working heartbeat waits from Boop's last
    /// reaction, not from the last event that woke the brain. Quick turns
    /// on another thread every 30 s don't hold off a long turn's heartbeats
    /// (45–90 s here); a reaction every 30 s does.
    func testTheWorkingHeartbeatWaitsFromBoopsLastReaction() {
        func beats(reacting: Bool) -> Int {
            let rig = CoreRig(seed: 7, rules: .chatty)
            rig.send(.turnStart, session: "long")
            var n = 0
            for _ in 0..<20 {
                n += workBeats(rig.wait(15_000)).count
                rig.send(.turnStart, session: "quick")
                n += workBeats(rig.wait(15_000)).count
                rig.send(.turnEnd, session: "quick")
                if reacting { rig.react() }
            }
            return n
        }
        XCTAssertGreaterThanOrEqual(beats(reacting: false), 6, "10 minutes of other threads' events")
        XCTAssertEqual(beats(reacting: true), 0, "a reaction every 30 s")
    }

    /// A new personality applies from the next event, with no restart.
    func testANewPersonalityAppliesAtOnce() {
        let rig = CoreRig(rules: Personality.Rules(workBeatMs: nil))
        rig.send(.turnStart)
        XCTAssertEqual(workBeats(rig.wait(300_000)), [], "no working heartbeat")
        rig.view.setRules(Personality.Rules(workBeatMs: 30_000...60_000))
        XCTAssertFalse(workBeats(rig.wait(61_000)).isEmpty, "a working heartbeat within 60 s")
    }

    /// A personality file's front matter, and its
    /// defaults for anything missing or unreadable.
    func testFrontMatter() {
        let chatter = Personality.Rules(frontMatter: "working_heartbeat: 30-60\ntool_uses: all")
        XCTAssertEqual(chatter, Personality.Rules(workBeatMs: 30_000...60_000, toolUses: .all))
        XCTAssertEqual(Personality.Rules(frontMatter: "working_heartbeat: none").workBeatMs, nil)
        XCTAssertEqual(Personality.Rules(frontMatter: "working_heartbeat: 60-30\ntool_uses: loud"), Personality.Rules())
        XCTAssertEqual(Personality.Rules(frontMatter: "chatter: 30-60"), Personality.Rules(),
                       "an older file's chatter is ignored: no rule mumbles")
    }
}

// MARK: - The working heartbeat, screen and inputs

final class CoreRulesTests: XCTestCase {
    /// Asleep only with no sessions, whatever the time.
    func testAsleepOnlyWithNoSessionsEvenLateAtNight() {
        let rig = CoreRig(start: CoreRig.start + 9 * 3600 * 1000)  // 23:00
        XCTAssertEqual(rig.state.base, "asleep")
        rig.send(.sessionStart)
        XCTAssertEqual(rig.state.base, "idle")
        rig.send(.turnStart)
        XCTAssertEqual(rig.state.base, "working")
    }

    func testNoSessionsIsAsleep() {
        XCTAssertEqual(CoreRig().state.base, "asleep")
    }

    /// Every 1.5–3 minutes of quiet
    /// work, day or night, the brain hears how long the thread working
    /// longest has worked, and on what.
    func testTheWorkingHeartbeatEveryOneAndAHalfToThreeMinutesOfQuietWork() {
        for start in [CoreRig.start, CoreRig.start + 9 * 3600 * 1000 + 1_800_000] {  // 14:00 and 23:30
            let rig = CoreRig(start: start, seed: 7)
            rig.send(.turnStart)
            rig.send(.activity, tool: "Bash", topic: "tests")
            var times: [Int64] = []
            var said: [String] = []
            for _ in 0..<3600 {
                let fx = rig.wait(1000)
                rig.send(.activity)  // keep it working
                for m in workBeats(fx) {
                    times.append(rig.now)
                    said.append(m)
                }
            }
            XCTAssertGreaterThan(times.count, 12)
            for (a, b) in zip(times, times.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b - a, 90_000)
                XCTAssertLessThanOrEqual(b - a, 181_000)
            }
            XCTAssertTrue(said.allSatisfy { $0.hasPrefix(#"claude is still working on "landing", a "#) && $0.hasSuffix(" turn, running tests.") })
        }
    }

    /// The wait counts from Boop's last reaction. An
    /// event that wakes the brain doesn't start it again, so a failure Boop
    /// didn't react to leaves the heartbeat due on time; one it reacted to
    /// starts the wait again.
    func testAReactionRestartsTheWorkingHeartbeatAndAnEventAloneDoesnt() {
        let rig = CoreRig(seed: 7, rules: Personality.Rules(workBeatMs: 60_000...60_000))
        rig.send(.turnStart)
        rig.wait(1000)  // the wait starts: due in 60 s
        rig.wait(50_000)
        XCTAssertEqual(woke(rig.send(.activity, tool: "Bash", topic: "tests", failed: true)).count, 1, "a failure wakes it")
        XCTAssertEqual(workBeats(rig.wait(20_000)).count, 1, "60 s after work started, with no reaction")
        rig.wait(50_000)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.react()
        XCTAssertEqual(workBeats(rig.wait(20_000)), [], "not 60 s after the last heartbeat: Boop reacted")
        XCTAssertEqual(workBeats(rig.wait(60_000)).count, 1, "60 s after the reaction")
    }

    func testNoWorkingHeartbeatWhenIdle() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(workBeats(rig.wait(600_000)), [])
    }

    /// The `state` message carries the busy and idle counts and
    /// the oldest session that needs you; the list is the popover's.
    func testSnapshotShapeAndSessionList() {
        let rig = CoreRig()
        rig.send(.sessionStart, .claude, session: "a", project: "notes")
        rig.send(.turnStart, .codex, session: "b", project: "buddygotchi")
        rig.send(.turnStart, .claude, session: "c", project: "jetpack")
        rig.send(.needsYou, .claude, session: "d", project: "landing", tool: "Bash")
        let s = rig.state
        XCTAssertEqual(rig.sessions, [["claude", "landing", "waiting"], ["codex", "buddygotchi", "working"],
                                      ["claude", "jetpack", "working"], ["claude", "notes", "idle"]])
        XCTAssertEqual([s.busy, s.waiting], [2, 1])
        let when = s.when.map { "\"\($0)\"" }.joined(separator: ",")
        XCTAssertEqual(s.jsonLine, #"{"t":"state","base":"working","mood":"calm","attn":{"agent":"claude","project":"landing","more":0,"id":1},"busy":2,"idle":1,"vol":6,"when":["# + when + "]}")
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(s.jsonLine.utf8)))
    }

    /// The `state` message carries the idle count, so a second idle
    /// session goes out as a new snapshot, and so does its end; with
    /// nothing changed, nothing goes out.
    func testAnIdleSessionShowsInTheState() {
        let rig = CoreRig()
        XCTAssertEqual(states(rig.send(.sessionStart, session: "a", project: "notes")).map(\.idle), [1])
        XCTAssertEqual(states(rig.send(.sessionStart, session: "b", project: "jetpack")).map(\.idle), [2])
        XCTAssertEqual(states(rig.send(.sessionEnd, session: "b", project: "jetpack")).map(\.idle), [1])
        XCTAssertEqual(rig.wait(5000).effects, [], "nothing changed")
        XCTAssertEqual(rig.state.waiting, 0)
    }

    /// Every `state` carries Boop's mood, calm (the
    /// resting mood) until the mood output says otherwise, and a new mood
    /// goes out at once.
    func testANewMoodGoesOutInTheNextState() {
        let rig = CoreRig()
        XCTAssertEqual(rig.state.mood, "calm")
        let fx = rig.setMood("determined")
        guard case .state(let s)? = fx.first, fx.count == 1 else {
            XCTFail("\(fx)")
            return
        }
        XCTAssertEqual(s.mood, "determined")
        XCTAssertEqual(rig.state.mood, "determined", "and every state after it")
    }

    func testNamesAreClippedToTheDevicesFields() {
        let rig = CoreRig()
        rig.send(.needsYou, session: "s", project: "a-really-long-project-name-number-1-for-the-sign-too", tool: "Bash")
        // A cut project name ends in "..", within the sign's 47 bytes.
        XCTAssertEqual(rig.state.attn?.project, "a-really-long-project-name-number-1-for-the-s..")
        XCTAssertEqual(rig.state.attn?.project.utf8.count, 47)
        XCTAssertEqual(rig.sessions.first?[1], "a-really-long-project-name-number-1-for-the-sign-too", "the popover shows it whole")
        XCTAssertLessThanOrEqual(rig.state.jsonLine.utf8.count, 512, "a line is at most 512 bytes (linkkit/SPEC.md §2)")
        XCTAssertEqual(StateSnapshot.clip("ünïcödé-ünïcödé-ünïcödé"), "ünïcödé-ünïcödé")
        XCTAssertEqual(StateSnapshot.clip("ünïcödé-ünïcödé-ünïcödé", marked: true), "ünïcödé-ünïcöd..")
        XCTAssertEqual(StateSnapshot.clip("a-23-byte-project-name!", marked: true), "a-23-byte-project-name!", "one that fits isn't marked")
        // Finder names folders decomposed (e and U+0301), which the device
        // draws as "e?": the Mac sends names precomposed, before measuring
        // them. Swift's == can't tell the two apart.
        let finder = CoreRig()
        finder.send(.needsYou, project: "cafe\u{301}", tool: "Bash")
        XCTAssertEqual(finder.state.attn.map { Array($0.project.utf8) }, [0x63, 0x61, 0x66, 0xC3, 0xA9])
        XCTAssertEqual(finder.sessions.first?[1], "cafe\u{301}", "the popover shows it as it came")
        let resume = "re\u{301}sume\u{301}-re\u{301}sume\u{301}-re\u{301}sume\u{301}"
        XCTAssertEqual(Array(StateSnapshot.clip(resume, marked: true).utf8), Array("r\u{E9}sum\u{E9}-r\u{E9}sum\u{E9}-r\u{E9}..".utf8), "23 bytes")
    }

    func testSnapshotsGoOutOnlyWhenSomethingChanged() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(states(rig.wait(5000)), [])
        XCTAssertEqual(states(rig.send(.activity)).count, 1)
        XCTAssertEqual(states(rig.send(.activity)).count, 0)
    }

    func testStaleWorkGoesIdleAndOldSessionsAreForgotten() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(3_600_000)
        XCTAssertEqual(rig.state.base, "idle")
        rig.wait(24 * 3_600_000, every: 60_000)
        XCTAssertEqual(rig.sessions, [])
    }

    func testSessionEndRemovesIt() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.send(.sessionEnd)
        XCTAssertEqual(rig.sessions, [])
        XCTAssertEqual(rig.state.base, "asleep")
    }

    /// A session that ended stays ended until it starts
    /// again (`session_start`, or a prompt). A hook of its that lands after
    /// its `SessionEnd` landed late: a permission `Notification` when you
    /// quit at the prompt, a background subagent's result or end, the
    /// command Codex's `Interrupt` aborted, a `Stop`. Before, each brought
    /// the session back: amber for 10 minutes that silenced every other
    /// session, working for an hour, or idle (awake at full backlight) for
    /// a day, and a late `Stop` cheered.
    func testALateHookAfterSessionEndDoesntBringItBack() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", id: "b")
        rig.send(.needsYou, tool: "Bash")
        rig.send(.sessionEnd)
        XCTAssertEqual(rig.state.base, "asleep")
        rig.now += 50
        XCTAssertEqual(rig.send(.needsYou).effects, [], "the late Notification")
        XCTAssertNil(rig.state.attn)

        rig.send(.turnStart, session: "bg")
        rig.send(.activity, session: "bg", tool: "Agent", id: "a")
        rig.send(.activity, session: "bg", subagent: "x", tool: "Bash", id: "x1")
        rig.send(.sessionEnd, session: "bg")
        var fx = rig.send(.activity, session: "bg", subagent: "x", tool: "Bash", failed: false, id: "x1")
        fx += rig.send(.subagentEnd, session: "bg", subagent: "x")
        fx += rig.send(.turnEnd, session: "bg")
        fx += rig.send(.turnStopped, session: "bg", notice: true)
        fx += rig.send(.activity, session: "bg", tool: "Read")
        XCTAssertEqual(events(fx), [])
        XCTAssertEqual(rig.state.base, "asleep")

        rig.send(.turnStart, .codex, session: "c")
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1")
        rig.send(.turnStopped, .codex, session: "c")  // Interrupt
        rig.send(.sessionEnd, .codex, session: "c")
        rig.send(.activity, .codex, session: "c", tool: "shell", id: "c1", done: true)
        XCTAssertEqual(rig.state.base, "asleep")
        XCTAssertEqual(workBeats(rig.wait(30 * 60_000)), [], "no working heartbeat")
        XCTAssertEqual(rig.sessions, [])

        // Another session is untouched: its finish wakes the brain.
        rig.send(.turnStart, session: "j", project: "jetpack")
        rig.send(.needsYou, session: "s1")
        XCTAssertNil(rig.state.attn)
        XCTAssertEqual(finished(rig.send(.turnEnd, session: "j", project: "jetpack")), ["done"])

        // Starting again brings it back: resumed, or a new prompt.
        rig.send(.sessionStart)
        XCTAssertEqual(rig.sessions, [["claude", "jetpack", "idle"], ["claude", "landing", "idle"]])
        XCTAssertEqual(woke(rig.send(.turnStart, session: "bg")), [#"claude started turn 1 on "landing"."#])
        XCTAssertEqual(rig.state.base, "working")

        // The mark lasts as long as a silent session is kept: a day.
        rig.wait(25 * 3_600_000, every: 60_000)
        rig.send(.activity, .codex, session: "c", tool: "shell")
        XCTAssertEqual(rig.state.base, "working", "a day on, it's a session Boop hasn't seen")
    }
}

// MARK: - The record and the screen agree

final class CoreFuzzTests: XCTestCase {
    /// Random hook traffic from three sessions, Claude with subagents and
    /// Codex, with ticks and clock jumps between, checked after every call
    /// against what the screen and HISTORY must agree on:
    /// - a `needs_you` event is for a session the core shows waiting
    ///   (one answered before it showed isn't recorded);
    /// - no event that wakes the brain while something needs you;
    /// - the state sent is the snapshot, and one request's number never
    ///   changes its agent or project;
    /// - a subagent's end, or a turn-level hook from inside a subagent,
    ///   answers only that subagent's request, isn't activity, and makes
    ///   the session work again only while its turn goes on;
    ///   a subagent's start changes none of that;
    /// - `act` only in the working look, the variant one of the visual's,
    ///   and the rules' reactions never while something needs you or with
    ///   an `id`, the error one at most every 30 s.
    func testRandomTrafficKeepsTheRecordAndTheScreenInStep() {
        var rng = SplitMix64(seed: 20260928)
        let rig = CoreRig()
        let sessions: [(Agent, String, String)] = [(.claude, "a", "landing"), (.claude, "b", "landing"),
                                                   (.codex, "c", "jetpack")]
        let tools = ["Bash", "Read", "Agent", "mcp__x__ask"]
        var lastAttn: StateSnapshot.Attention?
        var calls = 0, shown = 0, finishes = 0, acts = 0, shots = 0
        var lastError: Int64?
        var trail: [String] = []  // the last calls, for a failure's message
        for step in 0..<20_000 {
            var fx = Fx()
            let logBefore = rig.log.count
            let sentBefore = rig.sent.count
            let before = rig.core.sessions
            let roll = rng.int(in: 0...99)
            if roll < 10 {
                rig.now += Int64(rng.int(in: 1...(roll < 2 ? 700_000 : 3000)))
                fx = rig.note(Fx(rig.pipeline.tick(at: rig.now)))
            } else {
                rig.now += Int64(rng.int(in: 0...400))
                let (agent, session, project) = sessions[rng.int(in: 0...2)]
                let claude = agent == .claude
                let subagent = claude && rng.chance(40) ? ["a1", "a2"][rng.int(in: 0...1)] : nil
                let tool = tools[rng.int(in: 0...(claude ? 3 : 0))]
                let id = "t\(rng.int(in: 0...5))"
                switch rng.int(in: 0...14) {
                case 0: fx = rig.send(.turnStart, agent, session: session, project: project,
                                      mode: claude ? ["plan", "default", nil][rng.int(in: 0...2)] : nil)
                case 1, 2: fx = rig.send(.activity, agent, session: session, subagent: subagent, project: project, tool: tool, id: id)
                case 3, 4: fx = rig.send(.activity, agent, session: session, subagent: subagent, project: project, tool: tool,
                                         failed: claude ? rng.chance(20) : nil, id: id, done: true)
                case 5, 6: fx = rig.send(.needsYou, agent, session: session, subagent: subagent, project: project, tool: tool)
                case 7: fx = rig.send(.needsYou, agent, session: session, subagent: subagent, project: project,
                                      notice: claude ? rng.chance(70) : false,
                                      kind: rng.chance(50) ? "permission_prompt" : "elicitation_dialog")
                case 8: fx = rig.send(.turnEnd, agent, session: session, project: project)
                case 9: fx = rig.send(.turnStopped, agent, session: session, subagent: subagent, project: project,
                                      tool: rng.chance(50) ? tool : nil, notice: claude && rng.chance(50))
                case 10: fx = claude ? rig.send(.subagentEnd, agent, session: session, subagent: subagent ?? "a1", project: project) : Fx()
                case 11: fx = rig.send(.turnFailed, agent, session: session, subagent: subagent, project: project)
                case 12: fx = rig.send(.activity, agent, session: session, subagent: subagent, project: project)
                case 13: fx = rig.send(.sessionStart, agent, session: session, subagent: subagent, project: project,
                                       source: ["startup", "resume", "clear", "compact"][rng.int(in: 0...3)])
                default: fx = claude ? rig.send(.subagentStart, agent, session: session, subagent: subagent ?? "a2", project: project) : Fx()
                }
            }
            calls += 1
            trail = Array((trail + ["\(step): " + (roll < 10 ? "tick" : lastSent(rig, from: logBefore))]).suffix(12))
            let why = trail.joined(separator: "\n")
            let now = rig.core.snapshot(at: rig.now)
            let showing = rig.core.needsYouShowing
            if rig.sent.count > sentBefore, let e = rig.sent.last, AgentEvent(e).map(SessionFold.step) == .subagentStart, let agent = e.agent,
               let session = e.session, let b = before[SessionFold.key(agent, session)] {
                let a = rig.core.sessions[SessionFold.key(agent, session)]
                XCTAssertEqual(a?.lastEventAt, b.lastEventAt, "a subagent's start isn't activity\n\(why)")
                XCTAssertEqual(a?.working, b.working, why)
                XCTAssertEqual(a?.needsSince, b.needsSince, why)
                XCTAssertEqual(a?.askers, b.askers, why)
            }
            if rig.sent.count > sentBefore, let e = rig.sent.last, let id = e.subagent, let step = AgentEvent(e).map(SessionFold.step),
               step == .subagentEnd || SessionFold.turnLevel.contains(step), let agent = e.agent, let session = e.session {
                let key = SessionFold.key(agent, session)
                // Only when no timer of the session's could have acted first.
                if let b = before[key], rig.now - b.lastEventAt < SessionFold.safetyNetMs, let a = rig.core.sessions[key] {
                    XCTAssertEqual(a.lastEventAt, b.lastEventAt, "a subagent's end isn't activity\n\(why)")
                    XCTAssertEqual(a.turn.startedAt, b.turn.startedAt, why)
                    XCTAssertEqual(a.askers, b.askers.filter { $0.key != id }, "it answers \(id) alone\n\(why)")
                    if b.askers[id] == nil {
                        XCTAssertEqual(a.needsSince, b.needsSince, "\(id) never asked\n\(why)")
                        // A helper working on with no turn open is done once none of its calls runs.
                        let helperDone = step == .subagentEnd && a.turn.startedAt == nil && a.calls.isEmpty
                            && a.pendingSince == nil
                        XCTAssertEqual(a.working, b.working && !helperDone, why)
                    } else if a.needsSince == nil {
                        XCTAssertEqual(a.working, b.turn.startedAt != nil, "working again only while its turn goes on\n\(why)")
                    }
                } else if before[key] == nil, let a = rig.core.sessions[key] {
                    XCTAssertFalse(a.working || a.needsSince != nil, "a session first seen this way is idle\n\(why)")
                }
            }
            for event in events(fx) {
                if event.name == "tool wait" {
                    shown += 1
                    XCTAssertNotNil(event.about.flatMap { rig.core.sessions[$0]?.needsSince }, "\(event.line) never showed\n\(why)")
                }
                if event.wakesBrain { XCTAssertFalse(showing, "\(event.line) woke the brain\n\(why)") }
            }
            finishes += finished(fx).count
            for reaction in deviceReactions(fx) {
                shots += 1
                XCTAssertFalse(showing, "\(reaction.name) \(reaction.args) while something needs you\n\(why)")
                XCTAssertNil(reaction.mood, why)
                XCTAssertTrue(["starting", "stopped", "error", "helper_return"].contains(reaction.anim ?? ""), why)
                XCTAssertEqual(reaction.ctx != nil, reaction.anim == "starting", why)
                if reaction.anim == "error" {
                    if let last = lastError { XCTAssertGreaterThanOrEqual(rig.now - last, Core.errorEveryMs, why) }
                    lastError = rig.now
                }
            }
            for sent in states(fx) {
                XCTAssertTrue(sent.act == nil || (sent.base == "working" && sent.attn == nil), "\(sent.jsonLine)\n\(why)")
                XCTAssertTrue(sent.when.allSatisfy(Occasions.all.contains), why)
                if sent.act != nil { acts += 1 }
            }
            if let sent = states(fx).last {
                XCTAssertEqual(sent, now, why)
                if let a = sent.attn, let b = lastAttn, a.id == b.id {
                    XCTAssertEqual([a.agent, a.project], [b.agent, b.project], "one request, one place\n\(why)")
                }
                lastAttn = sent.attn ?? lastAttn
            }
        }
        XCTAssertGreaterThan(shown, 500, "the traffic asks often")
        XCTAssertGreaterThan(finishes, 100, "and finishes often")
        XCTAssertGreaterThan(acts, 500, "and shows what it's doing")
        XCTAssertGreaterThan(shots, 500, "and plays rule reactions")
        print("  \(calls) calls, \(shown) requests shown, \(finishes) finishes, \(acts) activities, \(shots) rule reactions")
    }
}

/// The last event `rig` sent, on one line, if it sent one since `from`
/// effects were logged.
func lastSent(_ rig: CoreRig, from: Int) -> String {
    guard let e = rig.sent.last else { return "-" }
    return "\(e.subagent.map { "(" + $0 + ") " } ?? "")\(e.summary)"
}
