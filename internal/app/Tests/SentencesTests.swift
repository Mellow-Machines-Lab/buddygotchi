import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Recorded sentences: a line of the pack that names its take
/// (`TaggedLine.take`) is said whole by the board when its voice has it in
/// the face shown, so what Boop says and what it shows are one choice
/// (`Asides`, `MomentOutput`). On Boop's own voice, which has every
/// sentence of the plan recorded.
@MainActor final class SentencesTests: XCTestCase {
    typealias Facts = [String: JSONValue]

    /// Boop's pack with no sentence in its voice table: what a Moment
    /// plays without them.
    static func plain() throws -> CharacterPack {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sentences-\(UUID().uuidString)")
        let boop = CharacterPackTests.repo.appendingPathComponent("characters/boop")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("mac"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: boop.appendingPathComponent("character.json"), to: dir.appendingPathComponent("character.json"))
        let table = try String(contentsOf: boop.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)
        let rows = table.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("sentence.") }
        try rows.joined(separator: "\n").write(to: dir.appendingPathComponent("mac/takes.tsv"), atomically: true, encoding: .utf8)
        return try CharacterPack(directory: dir)
    }

    func rig(_ pack: CharacterPack, talk: Talk = .normal, remarks: Bool = false) -> InviteRig {
        let rig = InviteRig()
        rig.pack = pack
        rig.talk = talk
        if remarks {
            let normals = RemarksTests.kept
            rig.react.remarking = MomentOutput.Remarking(normals: { normals }, minutes: { Int($0 / 60_000) % 1440 })
        }
        return rig
    }

    static var check: Event { AsidesTests.check }
    func win() -> Facts { AsidesTests().win() }
    func tests(_ result: String, before: Int64, topic: String = "tests") -> Facts { AsidesTests().check(result, before: before, topic: topic) }

    /// The text of the signs.md row that names `take`'s sentence, filled
    /// in as Asides fills it, `{what}` the rig's thread.
    static func row(_ take: Take) -> String? {
        RuntimeTests.steering.signs.first { $0.take == take.meaning }.flatMap { Asides.filled($0.text, what: "buddygotchi", n: nil) }
    }

    /// What a run sent: each Moment's takes' ids and its sign.
    func played(_ rig: InviteRig) -> [String] {
        rig.sent.map { ($0.say?.takes.map(\.id).joined(separator: "+") ?? "-") + " | " + ($0.sign ?? "-") }
    }

    /// At a win in a bright face, a recorded sentence wins over the rows
    /// with none: the finish says it whole, and its aside behind it is
    /// that row's text.
    func testARecordedSentenceIsSaidAndShown() throws {
        try requirePack("boop")
        let rig = rig(.active)
        let result = try XCTUnwrap(rig.run(AsidesTests.finish, win(), face: "proud"))
        let said = try XCTUnwrap(rig.sent.first?.say?.takes.first)
        XCTAssertEqual(said.part, .sentence)
        XCTAssertEqual(rig.sent.first?.say?.takes.count, 1, "said whole, no sound before it")
        let shown = try XCTUnwrap(rig.sent.last?.sign)
        XCTAssertEqual(Self.row(said), shown, "voice and text are one choice")
        XCTAssertEqual(result.facts["takes"], .array([.string(said.id)]))
    }

    /// Never the same sentence twice running, while another fits.
    func testNeverTheSameSentenceTwiceRunning() throws {
        try requirePack("boop")
        let rig = rig(.active)
        var last: String?
        for _ in 0..<8 {
            rig.sent = []
            rig.run(AsidesTests.finish, win(), face: "happy")
            let said = try XCTUnwrap(rig.sent.first?.say?.takes.first?.meaning)
            XCTAssertNotEqual(said, last)
            last = said
        }
    }

    /// With no sentence for the face, today's Moment exactly: the skit's
    /// word and the aside picked as before, as Boop's own pack does it.
    func testNoSentenceForTheFaceIsTodaysMoment() throws {
        try requirePack("boop")
        for (face, facts, e) in [("angry", win(), AsidesTests.finish), ("grumpy", tests("ok", before: 2), Self.check),
                                 ("happy", tests("failed", before: 0, topic: "build"), Self.check)] {
            let voiced = rig(.active), plain = rig(try Self.plain())
            voiced.run(e, facts, face: face)
            plain.run(e, facts, face: face)
            XCTAssertEqual(played(voiced), played(plain), face)
            XCTAssertFalse(voiced.sent.flatMap { $0.say?.takes ?? [] }.contains { $0.part == .sentence }, face)
        }
    }

    /// A named check's sentence fits only that check; and a failed check,
    /// which has no skit, speaks only with a sentence: a bright face has
    /// none.
    func testACheckSaysItsOwnSentence() throws {
        try requirePack("boop")
        let rig = rig(.active)
        for (topic, fits) in [("tests", ["oops.that", "oops.tests", "oops.tests-no"]), ("build", ["oops.that", "oops.build"])] {
            rig.sent = []
            rig.run(Self.check, tests("failed", before: 0, topic: topic), face: "determined")
            let said = try XCTUnwrap(rig.sent.first?.say?.takes.first)
            XCTAssertTrue(fits.contains(said.meaning), "the \(topic)' failure: \(said.meaning)")
            XCTAssertEqual(rig.sent.first?.low, true)
            if said.meaning != "oops.that" { XCTAssertEqual(rig.sent.first?.sign, Self.row(said)) }
        }
        rig.sent = []
        rig.run(Self.check, tests("failed", before: 0, topic: "build"), face: "happy")
        XCTAssertEqual(rig.sent.first?.say?.takes ?? [], [], "a bright face's failure: text only")
        XCTAssertNotNil(rig.sent.first?.sign)
    }

    /// A remark whose line names a recorded sentence says it.
    func testARemarkSaysItsSentence() throws {
        try requirePack("boop")
        let rig = rig(.active, remarks: true)
        rig.run(RemarksTests.finish(), RemarksTests().win(minutes: 2), face: "happy")
        XCTAssertEqual(rig.sent.first?.say?.takes.map(\.meaning), ["win.quick"])
        XCTAssertEqual(rig.sent.last?.sign, "that was fast", "the remark's own text")
    }

    /// You back says its sentence; its sign stays as it was.
    func testBackSaysItsSentenceOnly() throws {
        try requirePack("boop")
        let voiced = rig(.active), plain = rig(try Self.plain())
        let facts: Facts = ["away_ms": .int(20 * 60_000), "away": .string(Band.away(ms: 20 * 60_000))]
        voiced.run(RemarksTests.cameBack(), facts, face: "happy")
        plain.run(RemarksTests.cameBack(), facts, face: "happy")
        XCTAssertEqual(voiced.sent.first?.say?.takes.map(\.meaning), ["back.youre-back"])
        XCTAssertEqual(voiced.sent.map(\.sign), plain.sent.map(\.sign))
    }

    /// Quiet, a call (the board keeps quiet) and swearing gate as ever.
    func testTheGatesHold() throws {
        try requirePack("boop")
        let quiet = rig(.active, talk: .quiet)
        quiet.run(Self.check, tests("failed", before: 0), face: "determined")
        XCTAssertEqual(quiet.sent.first?.say?.takes ?? [], [])
        XCTAssertNil(quiet.sent.first?.sign)
        let call = rig(.active)
        call.react = MomentOutput(queue: { m, _ in call.sent.append(m) }, blocked: { nil }, speaks: { false }, pack: call.pack,
                                  signs: RuntimeTests.steering.signs, line: { _ in Line("", facts: call.facts) })
        call.run(AsidesTests.finish, win(), face: "happy")
        XCTAssertTrue(call.sent.allSatisfy { $0.say?.takes.isEmpty ?? true }, "a board that doesn't speak says nothing")
        // No swear: an upset sentence, never a swear row's.
        let upset = rig(.active)
        upset.run(AsidesTests.finish, AsidesTests().failed(), face: "sad")
        let said = try XCTUnwrap(upset.sent.first?.say?.takes.first)
        XCTAssertTrue(said.part == .sentence && said.meaning.hasPrefix("upset.") && said.kind != .swear, said.id)
        XCTAssertEqual(upset.sent.last?.sign, Self.row(said))
    }

    /// Jev's seat offers the sentences that fit, and its pick is said.
    func testJevPicksAmongTheSentences() throws {
        try requirePack("boop")
        let rig = rig(.active)
        rig.facts = win()
        let asked = rig.react.questions(now: AsidesTests.finish, log: Transcript.log().view(now: AsidesTests.finish.at))
        let options = try XCTUnwrap(asked.first { $0.key == MomentOutput.takeKey }).options.map(\.name)
        XCTAssertEqual(Set(options), ["Phew. Finally done!", "Big one! Done", "Long haul. But done!"], "a very long turn's, bright")
        for pick in options {
            rig.sent = []
            _ = rig.react.run([MomentOutput.emotionKey: Answer(choice: "happy", probabilities: ["happy": 1]),
                               MomentOutput.takeKey: Answer(choice: pick, probabilities: [pick: 1])],
                              now: AsidesTests.finish, log: Transcript.log().view(now: AsidesTests.finish.at))
            XCTAssertEqual(rig.sent.first?.say?.takes.map(\.text), [pick])
        }
    }

    /// A settings file from the spoken modes still loads: their keys are
    /// ignored, and nothing else changes.
    func testOldSettingsWithAVoiceStillLoad() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"talk":"quiet","volume":3,"voice":"cloud","cloudVoice":{"voice":"nova"}}"#.utf8))
        XCTAssertEqual(old.talk, .quiet)
        XCTAssertEqual(old.volume, 3)
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(written.contains("oice"))
    }
}
