import AgentHooks
import BoopKit
import Foundation

/// Replays recorded hook payloads through the same field picking as
/// `agent-hook` (with Boop's `--keep-text`), the adapter and a fresh core,
/// on a virtual clock. Used by the evals and the tests.
public struct Replay {
    /// A payload, a `{"wait_ms": N}` line that waits, or an
    /// `{"advance_ms": N}` line that jumps a live app's clock; on the virtual
    /// clock both are just time passing. Lines with `expect` or `expect_not`
    /// are `boopctl e2e` checkpoints, skipped.
    public enum Step: Equatable {
        case payload(Data)
        case wait(Int64)
        case advance(Int64)
    }

    /// 2026-10-14 14:00 UTC, a Wednesday, so output is repeatable. The
    /// evals and the tests start there too.
    public static let defaultStart: Int64 = 1_791_986_400_000

    public var agent: String
    /// Virtual time between payloads.
    public var gapMs: Int64 = 1000

    public init(agent: String) {
        self.agent = agent
    }

    /// `.jsonl` gives one step per line; `.json` is a single payload.
    public static func steps(fromFile path: String) throws -> [Step] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        if path.hasSuffix(".json") { return [.payload(Data(text.utf8))] }
        return text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               object["hook_event_name"] == nil {
                if let wait = object["wait_ms"] as? NSNumber { return .wait(wait.int64Value) }
                if let jump = object["advance_ms"] as? NSNumber { return .advance(jump.int64Value) }
                // Checkpoints for the pipeline check (`boopctl e2e`).
                if object["expect"] != nil || object["expect_not"] != nil { return nil }
            }
            return .payload(Data(line.utf8))
        }
    }

    /// Runs the steps and returns one line per raw event, core effect and
    /// view event, each effect and view event prefixed with its virtual
    /// time. `statesOnly` keeps only what goes to the device: each `state`
    /// and each rule reaction's `do`.
    public func run(_ steps: [Step], statesOnly: Bool = false) -> [String] {
        let start = Replay.defaultStart
        var now = start
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let core = Core(config: .init(time: time), lastActiveDay: time.day(now))
        let pipeline = Pipeline(core: core, view: TranscriptView())
        var out: [String] = []

        func emit(_ step: Pipeline.Step) {
            let at = "+" + String(format: "%.1f", Double(now - start) / 1000) + "s "
            for effect in step.effects {
                switch effect {
                case .state, .reaction: break
                default: if statesOnly { continue }
                }
                out.append(at + effect.summary)
            }
            if !statesOnly { for view in step.views { out.append(at + "view " + view.summary) } }
        }
        func advance(_ ms: Int64) {
            let end = now + ms
            while now < end {
                now = min(end, now + 1000)
                emit(pipeline.tick(at: now))
            }
        }

        core.tick(at: now)
        for step in steps {
            switch step {
            case .wait(let ms), .advance(let ms):
                advance(ms)
            case .payload(let data):
                guard let line = HookLine.extract(agent: agent, payload: data, ts: now, keepText: true) else {
                    if !statesOnly { out.append("# skipped: not a hook payload") }
                    continue
                }
                guard let event = Adapter.event(from: line) else {
                    if !statesOnly { out.append("# ignored hook \(line.hook)") }
                    continue
                }
                let step = pipeline.agentReadingPrompt(event)
                if !statesOnly, let recorded = step.recorded.first { out.append("event " + recorded.jsonLine) }
                emit(step)
                advance(gapMs)
            }
        }
        return out
    }
}
