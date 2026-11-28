import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Which take a skit says (`skit.take`, a seat of `SeatedBrain`): the texts
/// it may say now, those not said lately first, which the rules leave
/// unanswered; Jev's pick, any of them, said in the face it chose, or
/// today's pick when that face lacks it.
final class SkitTakeTests: XCTestCase {
    typealias Facts = [String: JSONValue]

    static let log = Transcript.log().view(now: 0)
    /// A long turn done: the win skit, a success.
    static let won: Facts = ["outcome": "done", "length": "long", "tools": 3, "length_ms": 120_000]

    func event(_ type: Event.Kind, _ phase: Event.Phase? = nil, _ specific: String = "Stop", data: Facts = [:]) -> Event {
        var e = Event(at: 0, source: .claude, type: type, phase: phase, specificType: specific, data: data)
        e.seq = 1
        return e
    }

    /// A Moment output on `pack` whose events' lines have `facts`, its
    /// Moments into `queued`.
    func output(_ pack: CharacterPack = .active, facts: Facts = SkitTakeTests.won, speaks: Bool = true, seed: UInt64 = 0x7A4E,
                queued: Queued = Queued()) -> MomentOutput {
        MomentOutput(queue: { m, _ in queued.all.append(m) }, blocked: { nil }, speaks: { speaks }, pack: pack,
                     line: { _ in Line("x", facts: facts) }, seed: seed)
    }

    final class Queued: @unchecked Sendable { var all: [Moment] = [] }

    func takeQuestion(_ out: MomentOutput, _ e: Event) -> Question? {
        out.questions(now: e, log: Self.log).first { $0.key == MomentOutput.takeKey }
    }

    func face(_ name: String) -> Answer { Answer(choice: name, probabilities: [name: 1]) }

    /// The win skit's texts that fit a success, as Voice gives them: of the
    /// kind its size asks, none that claims a fix.
    func winTexts(avoiding: [String] = []) -> [String] {
        let size = MomentOutput.sizes[MomentRule.size(event(.turn, .end), facts: Self.won, mood: nil)]
        return Voice.texts(.skit, meaning: "win", kind: size.kind, avoiding: avoiding,
                           never: CharacterPack.active.claimsAFix, limit: MomentOutput.takesOffered)
    }

    /// At a skit: its texts, each once, at most 6, no `none`, the one not
    /// said longest first; what it just said goes to the end. The rules
    /// leave it unanswered: Voice picks, as with no key.
    func testTheQuestionOffersTheSkitsTextsTheRulesAnswerNone() async throws {
        try requireVoice()
        XCTAssertEqual(MomentOutput.takesOffered, 6)
        let out = output()
        let e = event(.turn, .end)
        let q = try XCTUnwrap(takeQuestion(out, e))
        let names = q.options.map(\.name)
        XCTAssertEqual(names, winTexts())
        XCTAssertTrue((2...6).contains(names.count), "\(names)")
        XCTAssertEqual(Set(names).count, names.count, "each once")
        XCTAssertFalse(names.contains("none"))
        let own = Set(Take.all.filter { $0.part == .skit && $0.meaning == "win" }.map(\.text))
        XCTAssertTrue(Set(names).isSubset(of: own), "\(names)")
        // The rules leave it to Voice.
        let rules = RulesBrain(seed: 1, facts: { _ in Self.won }, mood: { _ in ("calm", 1) })
        let a = try await rules.reading(now: e, log: Self.log).answer(state: "", questions: [q], deadline: .seconds(1))
        XCTAssertNil(a[MomentOutput.takeKey])
        // Once it said one, that one is the last offered, or past the six.
        let face = try XCTUnwrap(RulesBrain.faces[.doneLong]?.first)
        _ = out.run([MomentOutput.emotionKey: self.face(face)], now: e, log: Self.log)
        let said = try XCTUnwrap(out.recentWords.last?.last)
        let after = try XCTUnwrap(takeQuestion(out, e)).options.map(\.name)
        XCTAssertNotEqual(after.first, said)
        if let at = after.firstIndex(of: said) { XCTAssertEqual(at, after.count - 1, "\(after)") }
        XCTAssertEqual(after, winTexts(avoiding: out.lastWords))
    }

    /// Never asked where no skit plays (a poke, a prompt, your words, a
    /// short turn), where it says nothing (no takes on the board), or with
    /// only one thing to say.
    func testNotAskedWithNoSkitNothingToSayOrOneOption() throws {
        try requireVoice()
        for (e, facts) in [(event(.poke, nil, "input"), [:]), (event(.prompt, nil, "UserPromptSubmit"), [:]),
                           (event(.said, nil, "said", data: ["words": "hi"]), [:]),
                           (event(.turn, .end), ["outcome": "done", "length": "short", "tools": 3, "length_ms": 20_000] as Facts)] {
            XCTAssertNil(takeQuestion(output(facts: facts), e), "\(e.kind) \(facts)")
        }
        XCTAssertNil(takeQuestion(output(speaks: false), event(.turn, .end)), "the board says nothing")
        XCTAssertNotNil(takeQuestion(output(), event(.turn, .end)))
        // A pack whose win has one take: nothing to choose.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("one-take-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("mac"), withIntermediateDirectories: true)
        try Data(#"""
            {"id": "one", "name": "One", "version": "1", "default_mood": "calm",
             "moods": [{"id": "calm", "face": "Calm."}], "lasting": [{"id": "calm", "meaning": "Settled."}],
             "skits": [{"id": "win", "slots": ["doneLong"]}]}
            """#.utf8).write(to: dir.appendingPathComponent("character.json"))
        try Data("1\nw1\tYes!\tskit\twin\tword\tcalm\t\t500\n".utf8).write(to: dir.appendingPathComponent("mac/takes.tsv"))
        let one = try CharacterPack(directory: dir)
        XCTAssertEqual(Take.all(in: one).count, 1)
        XCTAssertNil(takeQuestion(output(one), event(.turn, .end)), "one option: not asked")
    }

    /// The face the win plays in, and a text of the options it has a take
    /// of and one it has none of, if `pack` has such a face.
    func faceWithAndWithout(_ options: [String], in pack: CharacterPack) -> (face: String, has: String, lacks: String)? {
        let takes = Take.all(in: pack).filter { $0.part == .skit && $0.meaning == "win" }
        for face in CharacterPack.active.faces.map(\.name) {
            let mine = Set(takes.filter { $0.moods.contains(face) }.map(\.text))
            if let has = options.first(where: mine.contains), let lacks = options.first(where: { !mine.contains($0) }) {
                return (face, has, lacks)
            }
        }
        return nil
    }

    /// Boop's pack with `text`'s takes no longer playing in `face`.
    static func pack(dropping text: String, from face: String) throws -> CharacterPack {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gappy-\(UUID().uuidString)")
        let boop = CharacterPackTests.repo.appendingPathComponent("characters/boop")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("mac"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: boop.appendingPathComponent("character.json"), to: dir.appendingPathComponent("character.json"))
        let table = try String(contentsOf: boop.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)
        let rows = table.split(separator: "\n", omittingEmptySubsequences: false).map { row -> String in
            var f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 8, f[1] == text else { return String(row) }
            f[5] = f[5].split(separator: " ").filter { $0 != face }.joined(separator: " ")
            return f.joined(separator: "\t")
        }
        try rows.joined(separator: "\n").write(to: dir.appendingPathComponent("mac/takes.tsv"), atomically: true, encoding: .utf8)
        return try CharacterPack(directory: dir)
    }

    /// What Moment `answers` play at a long win, from a fresh output with
    /// the same seed: the texts it says.
    func said(_ answers: Answers, in pack: CharacterPack = .active) -> [String] {
        let queued = Queued()
        _ = output(pack, queued: queued).run(answers, now: event(.turn, .end), log: Self.log)
        return queued.all.first?.say?.takes.map(\.text) ?? []
    }

    /// Jev's pick is said in the face it chose, the first option too; one
    /// that face has no take of, or one not offered, says today's pick, as
    /// no answer does.
    func testThePickIsSaidInTheChosenFaceElseTodaysPick() throws {
        try requireVoice()
        let options = try XCTUnwrap(takeQuestion(output(), event(.turn, .end))).options.map(\.name)
        // Boop's own voice has every win text in every face (a word's flat
        // take fills in for the delivery it lacks): its table with the last
        // option gone from one face has a face that lacks one.
        let gappy = try Self.pack(dropping: try XCTUnwrap(options.last), from: "happy")
        let (face, has, lacks) = try XCTUnwrap(faceWithAndWithout(options, in: gappy), "a face with some of the texts and not others")
        let todays = said([MomentOutput.emotionKey: self.face(face)], in: gappy)
        XCTAssertFalse(todays.isEmpty, "\(face) says something at a win")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face(has)], in: gappy).last, has)
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face(lacks)], in: gappy), todays,
                       "\(lacks) isn't in \(face): today's pick")
        // The first option, in a face that has it and whose own pick today is another.
        let first = try XCTUnwrap(CharacterPack.active.faces.map(\.name).first { f in
            Take.all.contains { $0.part == .skit && $0.meaning == "win" && $0.text == options[0] && $0.moods.contains(f) }
                && said([MomentOutput.emotionKey: self.face(f)]).last != options[0]
        }, "a face that has \(options[0]) and picks another today")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(first), MomentOutput.takeKey: self.face(options[0])]).last, options[0],
                       "Jev may pick the first")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face("Not a take.")], in: gappy), todays,
                       "not offered: today's")
    }
}
