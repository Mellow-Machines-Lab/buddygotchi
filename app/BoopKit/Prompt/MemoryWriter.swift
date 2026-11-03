import Foundation
import FoundationModels

/// Writes the night's edits to the written memory: the request in, the
/// reply's plain lines out (`MemoryEdits` reads them). Nil when it can't: then the memory stays as
/// it was. A protocol, so a stub drives the tests and another model could
/// stand in later.
public protocol MemoryWriter: Sendable {
    func write(_ request: MemoryRequest) async -> MemoryWriterReply
    /// A note as the pet's own short line (`MemoryPipeline.signIsValid`).
    func sign(for note: String) async -> MemoryWriterSign
}

public extension MemoryWriter {
    func sign(for note: String) async -> MemoryWriterSign { .noAnswer }
}

/// What the writer made of a note, for a line. With no answer it's asked again
/// at the next dream: Apple Intelligence may be off for now, or have timed out.
/// A line the checks refuse is final for that note.
public enum MemoryWriterSign: Equatable, Sendable {
    case line(String), refused, noAnswer
}

public enum MemoryWriterReply: Equatable, Sendable {
    case reply(String)
    case none
}

/// The dream's request: what the writer works from, and the notes as its
/// reply numbers them.
public struct MemoryRequest: Equatable, Sendable {
    /// The ids of the notes numbered 1 to N, in order.
    public var numbered: [Int]
    public var pipeline: MemoryPipeline.Input

    public init(_ pipeline: MemoryPipeline.Input) {
        self.pipeline = pipeline
        numbered = pipeline.memory.numbered
    }

    /// CERTAIN, from the span's tallies and its dates (`range`): "From
    /// Monday 2026-10-26 to Tuesday 2026-10-27. You were at the Mac 7 hours,
    /// stroked Boop 3 times and talked to it twice. Agents finished 9
    /// turns, 1 failed, most on "api"."
    public static func certain(_ t: MemoryReader.Tallies, range: String) -> String {
        func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }
        var you: [String] = []
        if t.hereMinutes >= 60 { you.append("were at the Mac \(t.hereMinutes / 60) hour\(t.hereMinutes / 60 == 1 ? "" : "s")") }
        if t.strokes > 0 { you.append("stroked Boop \(times(t.strokes))") }
        if t.pokes > 0 { you.append("poked it \(times(t.pokes))") }
        if t.talks > 0 { you.append("talked to it \(times(t.talks))") }
        var out = range.contains(" to ") ? "From \(range)." : "On \(range)."
        if !you.isEmpty {
            out += " You " + (you.count == 1 ? you[0] : you.dropLast().joined(separator: ", ") + " and " + you.last!) + "."
        }
        out += t.turns == 0 ? " Agents finished no turns."
            : " Agents finished \(t.turns) turn\(t.turns == 1 ? "" : "s"), \(t.failed) failed, most on \"\(t.thread)\"."
        return out
    }

    /// The person's words in the lines since the last dream (`Your words: "…"`), which a
    /// note may quote.
    public static func words(in journal: [(at: String, line: String)]) -> [String] {
        journal.flatMap { entry -> [String] in
            entry.line.components(separatedBy: "\n").filter { $0.contains("Your words") || $0.contains("You said to") }
        }
    }
}

/// The write as `MemoryPipeline` does it: code proposes, and Apple Intelligence
/// on the Mac answers small questions, each in a fresh session, for at most
/// `AppleIntelligenceMemoryModel.timeout`. With the model off, code writes alone:
/// the habits and sagas still come; the moments, the stories and anything
/// else in your words wait.
public struct MemoryPipelineWriter: MemoryWriter {
    public init() {}

    public func write(_ request: MemoryRequest) async -> MemoryWriterReply {
        .reply(await MemoryPipeline.write(request.pipeline, model: Self.model))
    }

    public func sign(for note: String) async -> MemoryWriterSign {
        guard let model = Self.model else { return .noAnswer }
        return await MemoryPipeline.sign(for: note, model: model)
    }
}

extension MemoryPipelineWriter {
    /// The Mac's model, or nil where Apple Intelligence is off.
    static var model: MemoryModel? {
        guard #available(macOS 26.0, *), AppleIntelligenceLabeler.isAvailable else { return nil }
        return AppleIntelligenceMemoryModel()
    }
}

/// `MemoryModel` on the Mac's model. Yes or no is guided; a refusal or a timeout
/// is nil, which every question takes as no to writing anything.
@available(macOS 26.0, *)
public struct AppleIntelligenceMemoryModel: MemoryModel {
    public static let timeout: Duration = .seconds(15)
    public init() {}

    public func text(_ instructions: String, _ prompt: String, tokens: Int) async -> String? {
        await AppleIntelligenceLabeler.within(Self.timeout) {
            let session = LanguageModelSession(model: AppleIntelligenceLabeler.OnDevice.model, instructions: instructions)
            return try? await session.respond(to: prompt, options: AppleIntelligenceLabeler.OnDevice.greedy(tokens: tokens)).content
        }
    }

    public func yes(_ instructions: String, _ prompt: String) async -> Bool? {
        await AppleIntelligenceLabeler.within(Self.timeout) {
            guard let schema = try? GenerationSchema(root: DynamicGenerationSchema(name: "Answer", anyOf: ["yes", "no"]), dependencies: []) else { return nil }
            let session = LanguageModelSession(model: AppleIntelligenceLabeler.OnDevice.model, instructions: instructions)
            guard let reply = try? await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: false, options: AppleIntelligenceLabeler.OnDevice.greedy(tokens: 20)),
                  let answer = try? reply.content.value(String.self) else { return nil }
            return answer == "yes"
        }
    }
}
