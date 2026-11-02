import BoopKit
import Foundation
import MellowHarness

/// How many real requests `boopdev eval` may send Jev in a local day, across
/// every command and worktree (internal/EVALS.md §2). The count is one file
/// outside the worktrees, locked for each change, so a loop of small runs
/// adds up. An expect brain's passes and the Boop app's own don't count.
public final class JevAllowance: @unchecked Sendable {
    /// The limit. Raise it here.
    public static let dailyLimit = 2500
    /// Set to 1 to go past the limit: only when the owner says so, for that request.
    public static let overrideVariable = "BOOP_JEV_OVER_LIMIT"
    /// `NSHomeDirectory()` ignores `HOME`, so a temporary `HOME` can't start a new count.
    public static var defaultFile: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".boopdev/jev-requests.json")
    }

    public static func overriddenByEnvironment() -> Bool {
        ProcessInfo.processInfo.environment[overrideVariable] == "1"
    }

    struct Count: Codable, Equatable {
        var day: String
        var used: Int
    }

    public let file: URL
    public let limit: Int
    public let overridden: Bool
    let today: () -> String

    public init(file: URL = JevAllowance.defaultFile, limit: Int = JevAllowance.dailyLimit, overridden: Bool = false,
                today: @escaping () -> String = {
                    LocalTime(timeZone: .current).day(Int64(Date().timeIntervalSince1970 * 1000))
                }) {
        self.file = file
        self.limit = limit
        self.overridden = overridden
        self.today = today
    }

    /// Today's requests so far.
    public func used() throws -> Int { try locked { $0.used } }

    /// Why a run of about `estimate` requests may not start, or nil when it
    /// may. A whole full run always needs the override, even when it would fit.
    public func refusal(estimate: Int, wholeFullRun: Bool = false) throws -> String? {
        let used = try used()
        let left = max(0, limit - used)
        if wholeFullRun, !overridden {
            return "a whole full run is only for when the owner asks: \(Self.overrideVariable)=1. "
                + "About \(estimate) requests, with \(used) used and \(left) left today."
        }
        guard estimate > left, !overridden else { return nil }
        return "today's limit of \(limit) Jev requests: \(used) used, \(left) left, and this run is about \(estimate). "
            + "Narrow it with --only or a lower --level. Only when the owner says so: \(Self.overrideVariable)=1"
    }

    /// Counts one request, or says false when the limit is reached.
    public func take() throws -> Bool {
        try locked { count in
            guard overridden || count.used < limit else { return false }
            count.used += 1
            return true
        }
    }

    /// Runs `change` on today's count with the file locked, and saves it if it changed. A
    /// file that can't be read or written throws: with no count, no requests.
    func locked<T>(_ change: (inout Count) -> T) throws -> T {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw EvalError("can't open \(file.path): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw EvalError("can't lock \(file.path): \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: fd)
        let data = try handle.readToEnd() ?? Data()
        let day = today()
        var count = Count(day: day, used: 0)
        if !data.isEmpty {
            let saved: Count
            do { saved = try JSONDecoder().decode(Count.self, from: data) } catch { throw EvalError("\(file.path) doesn't read: \(error)") }
            if saved.day == day { count = saved }
        }
        let before = count
        let out = change(&count)
        guard count != before else { return out }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: JSONEncoder().encode(count))
        return out
    }
}

/// A brain whose every answer is counted against the `JevAllowance`. Past
/// the limit it asks nothing and says `stopped`, so the run can end cleanly.
public final class CountedBrain: Brain, @unchecked Sendable {
    let inner: any Brain
    let allowance: JevAllowance
    private let lock = NSLock()
    private var counted = 0
    private var stop: String?

    public init(_ inner: any Brain, allowance: JevAllowance) {
        self.inner = inner
        self.allowance = allowance
    }

    public var id: String { inner.id }
    /// The requests this brain sent.
    public var requests: Int { lock.withLock { counted } }
    /// Why it stopped asking, once it has.
    public var stopped: String? { lock.withLock { stop } }

    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        let why: String?
        do {
            why = try allowance.take() ? nil : "today's limit of \(allowance.limit) Jev requests is reached"
        } catch {
            why = "\(error)"
        }
        if let why {
            lock.withLock { stop = why }
            throw BrainError(why)
        }
        lock.withLock { counted += 1 }
        return try await inner.answer(state: state, questions: questions, deadline: deadline)
    }
}
