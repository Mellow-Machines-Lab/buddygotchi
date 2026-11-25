import Foundation
import MellowHarness

/// The one brain every real launch has: the rules always answer, at once
/// and with no network (`RulesBrain`), and Jev, with a key, may replace an
/// answer in one of its seats (`seats`). Jev is asked the same state and
/// questions; its answer to a seat replaces the rules' only if it comes
/// within the pass's deadline, less `margin`, and names one of that
/// question's options. A slow, failing, absent or wrong Jev changes nothing
/// a person sees: the pass plays on the rules' answers, and how Jev did
/// goes to `report`, never to the harness as a dropped pass. It keeps
/// nothing between passes: each reads the transcript and the pass alone.
public final class SeatedBrain: ReadingBrain, @unchecked Sendable {
    /// The questions Jev may answer in the rules' place: the mood, the
    /// face, a reply to your words and its sign, and which take a skit
    /// says. The sign is a seat on every pass, so whichever brain answered
    /// a prompt's caption, an idle beat or a dream's sign before still
    /// does. Any other question stays the rules'.
    public static let seats: Set<String> = [MoodOutput.outputName, MomentOutput.emotionKey, MomentOutput.replyKey,
                                            Signs.questionKey, MomentOutput.takeKey]
    /// How long before the pass's deadline Jev's answer must be in, so the
    /// rules' answers reach the outputs within it.
    public static let margin: Duration = .milliseconds(100)

    public var id: String { jev?.id ?? rules.id }
    let rules: RulesBrain
    let jev: (any Brain)?
    let margin: Duration
    /// After each pass that asked Jev: nil when it answered in time, else
    /// why not. Off the harness's queue.
    let report: @Sendable (BrainError?) -> Void

    public init(rules: RulesBrain, jev: (any Brain)?, margin: Duration = SeatedBrain.margin,
                report: @escaping @Sendable (BrainError?) -> Void = { _ in }) {
        self.rules = rules
        self.jev = jev
        self.margin = margin
        self.report = report
    }

    public func reading(now: Event, log: LogView) -> any Brain {
        Call(rules: rules.reading(now: now, log: log), jev: (jev as? any ReadingBrain)?.reading(now: now, log: log) ?? jev,
             margin: margin, report: report)
    }

    /// Asked with no reading: the rules' answers with none, and Jev's in
    /// their seats.
    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try await Call(rules: rules, jev: jev, margin: margin, report: report).answer(state: state, questions: questions, deadline: deadline)
    }

    /// One pass's answers: the rules' first, then Jev's in its seats.
    struct Call: Brain {
        var id: String { jev?.id ?? rules.id }
        let rules: any Brain
        let jev: (any Brain)?
        let margin: Duration
        let report: @Sendable (BrainError?) -> Void

        func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
            var out = try await rules.answer(state: state, questions: questions, deadline: deadline)
            guard let jev else { return out }
            let limit = max(.zero, deadline - margin)
            switch await SeatedBrain.within(limit, { try await jev.answer(state: state, questions: questions, deadline: limit) }) {
            case .failure(let error):
                report(error)
            case .success(let answers):
                report(nil)
                for q in questions where SeatedBrain.seats.contains(q.key) {
                    if let a = answers[q.key], q.options.contains(where: { $0.name == a.choice }) { out[q.key] = a }
                }
            }
            return out
        }
    }

    /// `body`'s answers, or why there are none: it failed, or took longer
    /// than `limit`, and then it's cancelled and not waited for.
    static func within(_ limit: Duration, _ body: @escaping @Sendable () async throws -> Answers) async -> Result<Answers, BrainError> {
        await withCheckedContinuation { done in
            let once = Once(done)
            let asked = Task {
                do {
                    once.finish(.success(try await body()))
                } catch let error as BrainError {
                    once.finish(.failure(error))
                } catch {
                    once.finish(.failure(BrainError("\(error)")))
                }
            }
            once.timing(Task {
                try? await Task.sleep(for: limit)
                if once.finish(.failure(BrainError("late: no answer within \(Int(limit / .milliseconds(1))) ms"))) { asked.cancel() }
            })
        }
    }

    /// A race's continuation, resumed once, with whichever result comes
    /// first; the timer is cancelled once one has.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done: CheckedContinuation<Result<Answers, BrainError>, Never>?
        private var timer: Task<Void, Never>?

        init(_ done: CheckedContinuation<Result<Answers, BrainError>, Never>) { self.done = done }

        func timing(_ timer: Task<Void, Never>) {
            let over = lock.withLock {
                if done == nil { return true }
                self.timer = timer
                return false
            }
            if over { timer.cancel() }
        }

        /// Whether this result was the first.
        @discardableResult
        func finish(_ result: Result<Answers, BrainError>) -> Bool {
            let (first, timer) = lock.withLock {
                defer { done = nil }
                return (done, self.timer)
            }
            guard let first else { return false }
            timer?.cancel()
            first.resume(returning: result)
            return true
        }
    }
}
