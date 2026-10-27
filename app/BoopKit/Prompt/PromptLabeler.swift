import Foundation
import FoundationModels

/// Labels a scrubbed prompt, or an agent's last message: its kind, its
/// tone, and phrases of it, from `Of`'s lists. Nil when it can't, which
/// leaves the reading counted only.
public protocol PromptLabeler: Sendable {
    func label<Of: ReadingText>(_ text: String, as: Of.Type) async -> Reading<Of>.Labels?
}

/// Apple Intelligence's on-device model, so the prompt never leaves the
/// Mac, and nor does the agent's last message. The model is macOS 26's;
/// Boop runs from macOS 14, where there's no labeler (`onThisMac` is nil).
/// It asks whether Apple Intelligence is on whenever it has no session
/// ready, so turning it on later works, and labels nothing while it's
/// off, or on an Intel Mac. It answers in three plain lines, which its
/// permissive guardrails allow where a structured answer would be refused
/// for a word like "kill" or "nuke"; anything off the lists is dropped.
/// Greedy, so the same prompt reads the same way.
public struct AppleIntelligenceLabeler: PromptLabeler {
    /// How long a reading may take before the counted one goes alone.
    public static let timeout: Duration = .seconds(3)

    /// The labeler on macOS 26, nil before it.
    public static var onThisMac: AppleIntelligenceLabeler? {
        guard #available(macOS 26.0, *) else { return nil }
        return AppleIntelligenceLabeler()
    }

    /// Whether Apple Intelligence can label now: macOS 26, an Apple
    /// silicon Mac, and the feature turned on.
    public static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return OnDevice.model.availability == .available
    }

    /// The labeler, or nil where Apple Intelligence isn't available now:
    /// for the tools, which say so.
    public static func ifAvailable() -> AppleIntelligenceLabeler? { isAvailable ? AppleIntelligenceLabeler() : nil }

    /// The model, where macOS has it, and a session ready for each list's
    /// next text: a session keeps what it was asked, so each text gets a
    /// fresh one, made and prewarmed once the last answered.
    @available(macOS 26.0, *)
    enum OnDevice {
        static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        static let ready = Ready()
        // The same answer for the same text. The macOS 27 SDK (Swift 6.4)
        // renamed `sampling:` to `samplingMode:`; CI's is the macOS 26 SDK's.
        #if compiler(>=6.4)
        static let greedy = GenerationOptions(samplingMode: .greedy)
        #else
        static let greedy = GenerationOptions(sampling: .greedy)
        #endif

        /// Its answer for `text`, quoted after `quoting` as the examples
        /// in `instructions` are; nil while Apple Intelligence is off.
        /// With no session ready (the first text, or after one went
        /// unanswered) it asks whether it's on first.
        static func respond(_ text: String, _ instructions: String, quoting: String) async -> String? {
            guard let session = ready.take(instructions)
                    ?? (model.availability == .available ? LanguageModelSession(model: model, instructions: instructions) : nil),
                  let reply = try? await session.respond(to: "\(quoting): \"\(text)\"", options: greedy)
            else { return nil }
            let next = LanguageModelSession(model: model, instructions: instructions)
            next.prewarm()
            ready.put(next, for: instructions)
            return reply.content
        }

        /// The sessions ready, by their instructions.
        final class Ready: @unchecked Sendable {
            let lock = NSLock()
            var sessions: [String: LanguageModelSession] = [:]
            func take(_ instructions: String) -> LanguageModelSession? { lock.withLock { sessions.removeValue(forKey: instructions) } }
            func put(_ session: LanguageModelSession, for instructions: String) { lock.withLock { sessions[instructions] = session } }
        }
    }

    /// The model's answer from `Of`'s lists, or nil at `timeout`,
    /// whichever comes first: the wait ends then even if the model takes
    /// its time to stop.
    public func label<Of: ReadingText>(_ text: String, as: Of.Type) async -> Reading<Of>.Labels? {
        guard #available(macOS 26.0, *) else { return nil }
        let instructions = Of.instructions, quoting = Of.quoting
        return await Self.within(Self.timeout) {
            await OnDevice.respond(text, instructions, quoting: quoting).map(Self.parse)
        }
    }

    /// `work`'s answer, or nil at `timeout`, whichever comes first: the
    /// one cancels the other.
    static func within<T: Sendable>(_ timeout: Duration, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            let first = First(done)
            let task = Task { await work() }
            let timer = Task {
                guard (try? await Task.sleep(for: timeout)) != nil else { return }
                task.cancel()
                first.resume(nil)
            }
            Task {
                first.resume(await task.value)
                timer.cancel()
            }
        }
    }

    /// Resumes a continuation once, with whichever answer comes first.
    final class First<T: Sendable>: @unchecked Sendable {
        let lock = NSLock()
        var done: CheckedContinuation<T?, Never>?
        init(_ done: CheckedContinuation<T?, Never>) { self.done = done }
        func resume(_ answer: T?) {
            lock.withLock { () -> CheckedContinuation<T?, Never>? in defer { done = nil }; return done }?.resume(returning: answer)
        }
    }

    /// The three lines' answers; a value off its list is none.
    static func parse<Of>(_ reply: String) -> Reading<Of>.Labels {
        var labels = Reading<Of>.Labels()
        for line in reply.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "kind": labels.kind = Of.Kind(rawValue: parts[1].lowercased())
            case "tone": labels.tone = Of.Tone(rawValue: parts[1].lowercased())
            case "phrases" where parts[1].lowercased() != "none":
                labels.phrases = parts[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            default: break
            }
        }
        return labels
    }
}
