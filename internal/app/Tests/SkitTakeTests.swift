import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Which take a skit says (`skit.take`, a seat of `SeatedBrain`): the texts
/// it may say now, the rules' pick first; the brain's pick said in the face
/// it chose, or today's pick when that face lacks it.
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
        return Voice.texts(.skit, meaning: "win", kind: size.kind, finish: "success", avoiding: avoiding,
                           never: CharacterPack.active.claimsAFix, limit: MomentOutput.takesOffered)
    }

    /// At a skit: its texts, each once, at most 6, no `none`, the one not
    /// said longest first; what it just said goes to the end. The rules
    /// answer with the first.
    func testTheQuestionOffersTheSkitsTextsTheRulesPickFirst() async throws {
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
        // The rules' answer: the first.
        let rules = RulesBrain(seed: 1, facts: { _ in Self.won }, mood: { _ in ("calm", 1) })
        let a = try await rules.reading(now: e, log: Self.log).answer(state: "", questions: [q], deadline: .seconds(1))
        XCTAssertEqual(a[MomentOutput.takeKey]?.choice, names.first)
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
             "moods": [{"id": "calm", "face": "Calm.", "meaning": "Settled."}],
             "skits": [{"id": "win", "slots": ["doneLong"]}]}
            """#.utf8).write(to: dir.appendingPathComponent("character.json"))
        try Data("1\nw1\tYes!\tskit\twin\tword\tcalm\t\t500\n".utf8).write(to: dir.appendingPathComponent("mac/takes.tsv"))
        let one = try CharacterPack(directory: dir)
        XCTAssertEqual(Take.all(in: one).count, 1)
        XCTAssertNil(takeQuestion(output(one), event(.turn, .end)), "one option: not asked")
    }

    /// The face the win plays in, and a text of the options it has a take
    /// of and one it has none of, if the pack has such a face.
    func faceWithAndWithout(_ options: [String]) -> (face: String, has: String, lacks: String)? {
        let takes = Take.all.filter { $0.part == .skit && $0.meaning == "win" && ($0.finish == nil || $0.finish == "success") }
        for face in CharacterPack.active.faces.map(\.name) {
            let mine = Set(takes.filter { $0.moods.contains(face) }.map(\.text))
            if let has = options.dropFirst().first(where: mine.contains), let lacks = options.dropFirst().first(where: { !mine.contains($0) }) {
                return (face, has, lacks)
            }
        }
        return nil
    }

    /// What Moment `answers` play at a long win, from a fresh output with
    /// the same seed: the texts it says.
    func said(_ answers: Answers) -> [String] {
        let queued = Queued()
        _ = output(queued: queued).run(answers, now: event(.turn, .end), log: Self.log)
        return queued.all.first?.say?.takes.map(\.text) ?? []
    }

    /// The brain's pick is said in the face it chose; one that face has no
    /// take of, or the rules' own (the first), says today's pick, as no
    /// answer does.
    func testThePickIsSaidInTheChosenFaceElseTodaysPick() throws {
        try requireVoice()
        let options = try XCTUnwrap(takeQuestion(output(), event(.turn, .end))).options.map(\.name)
        let (face, has, lacks) = try XCTUnwrap(faceWithAndWithout(options), "a face with some of the texts and not others")
        let todays = said([MomentOutput.emotionKey: self.face(face)])
        XCTAssertFalse(todays.isEmpty, "\(face) says something at a win")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face(has)]).last, has)
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face(lacks)]), todays,
                       "\(lacks) isn't in \(face): today's pick")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face(options[0])]), todays,
                       "the rules' pick: today's")
        XCTAssertEqual(said([MomentOutput.emotionKey: self.face(face), MomentOutput.takeKey: self.face("Not a take.")]), todays,
                       "not offered: today's")
    }
}
