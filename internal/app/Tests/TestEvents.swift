import Foundation
import MellowHarness
@testable import BoopDevKit
@testable import BoopKit

/// When the harness tests start, in unix milliseconds.
let harnessT0: Int64 = 1_790_000_000_000

/// Actions as the tests name them: before MellowHarness an action was an
/// event of its own type, with a phase; now it's MellowHarness's `did` (open
/// while it plays), its `ended`, or, for "needs you", Boop's own
/// `needs_you_start` and `needs_you_end`.
extension Event {
    /// An action named `name`: `.end` is its `ended` (`for` its `did`),
    /// `.start` an open `did`, nil a plain one.
    static func action(at: Int64, phase: Phase? = nil, name: String, data: [String: JSONValue] = [:]) -> Event {
        var data = data
        data["action"] = .string(name)
        switch phase {
        case .end?: return Event(at: at, source: Event.harness, kind: Event.ended, data: data)
        case .start?: data["open"] = true
        default: break
        }
        return Event(at: at, source: Event.harness, kind: Event.did, data: data)
    }

    /// `data` without Boop's own fields (`specific_type`, `session`,
    /// `subagent`, `cwd`), which were at the top of an event before
    /// MellowHarness, and an action's name.
    var fields: [String: JSONValue] { data.filter { !Event.metaKeys.contains($0.key) && $0.key != "action" } }

    /// A `did`, an `ended` or "needs you": what was an action.
    var isAction: Bool { kind == Event.did || kind == Event.ended || type == .needsYou }

    /// The action's name: the output's or rule's, or `needs_you`.
    var actionName: String { action ?? specificType }

    /// The action's phase as it was: an `ended` is its end, an open `did`
    /// its start, "needs you" its own.
    var actionPhase: Phase? {
        if type == .needsYou { return phase }
        if kind == Event.ended { return .end }
        return self["open"]?.bool == true ? .start : nil
    }
}

/// What the tests read of a pipeline, past the step each input returns.
extension Pipeline {
    /// Logs an event nothing else acts on, such as an action's.
    @discardableResult
    func record(_ event: Event) -> Event {
        var logged = event
        _ = input(at: max(inputTime.now, event.at)) { logged = harness.emit(event) }
        return logged
    }

    /// Whether you're away from the Mac, as the log has it.
    var away: Bool { view.away(transcript.view(now: inputTime.now)) }

    /// The event `seq` with its line and what the rules did about it, as
    /// it stands now; nil for one with no line.
    func viewEvent(_ seq: Int) -> ViewEvent? {
        guard let e = transcript.event(seq), let line = harness.line(seq),
              var v = view.view(e, line, wakes: false, log: transcript.view(before: e)) else { return nil }
        v.wakesBrain = harness.wakes(e) && whyNotWake(e) == nil
        v.did = shown(dids: seq, transcript.view(now: inputTime.now))
        return v
    }

    /// Every event with a line in the log, oldest first.
    var views: [ViewEvent] { transcript.events.compactMap { viewEvent($0.seq) } }
}

/// A test case that runs the whole runtime headless on a state directory
/// of its own under /tmp, on a virtual clock, with dev lines standing in
/// for the Mac's signals and no link, brain or Jev key.
@MainActor protocol HeadlessRig: AnyObject {
    var dir: URL! { get set }
}

extension HeadlessRig {
    /// A new state directory, `/tmp/boop-NAME-…`: short, for the socket.
    func makeDir(_ name: String) throws {
        try requirePack("boop")
        dir = URL(fileURLWithPath: "/tmp/boop-\(name)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func removeDir() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func makeRuntime(clock: VirtualClock) throws -> Runtime {
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("long-term.md").path) {
            try Runtime.setUp(stateDir: dir, name: "Pip")
        }
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.alone = true
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.advance = { clock.now += $0 }
        options.readJevKey = { _ in nil }
        return try Runtime(options)
    }

    func dev(_ runtime: Runtime, _ json: String) {
        runtime.home.sync { runtime.dev(Data(json.utf8)) }
    }
}
