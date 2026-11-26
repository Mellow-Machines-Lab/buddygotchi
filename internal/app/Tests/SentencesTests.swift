import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Recorded sentences: a line of the pack that names its take
/// (`TaggedLine.take`) is said whole by the board when its voice has it in
/// the face shown, so what Boop says and what it shows are one choice
/// (`Asides`, `MomentOutput`). On a voice table with a few of tier 1's
/// sentences recorded; Boop's own has none yet.
@MainActor final class SentencesTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    static let bright = "happy pleased amused affectionate excited proud mischievous smug"
    static let flat = "calm focused determined curious surprised"
    static let glum = "sad lonely faint annoyed grumpy angry silent_scream wounded"
    /// The sentences recorded in the fixture, as voicegen would list them.
    static let recorded = [
        ("win.all-yours", "Done! All yours", bright), ("win.high-five", "High five! Done", bright),
        ("upset.it-broke", "Aw. It broke", glum), ("oops.tests", "Uh oh. The tests failed", flat),
        ("win.quick", "That was quick!", bright), ("back.youre-back", "Oh! You're back!", bright),
    ]

    /// Boop's pack with the fixture's voice table: its own takes and the
    /// recorded sentences.
    static func voiced() throws -> CharacterPack {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sentences-\(UUID().uuidString)")
        let boop = CharacterPackTests.repo.appendingPathComponent("characters/boop")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("mac"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: boop.appendingPathComponent("character.json"), to: dir.appendingPathComponent("character.json"))
        let table = try String(contentsOf: boop.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)
        let rows = recorded.map { id, text, faces in
            let mood = faces == bright ? "happy" : faces == flat ? "calm" : "sad"
            return "sentence.\(id)__\(mood)\t\(text)\tsentence\t\(id)\tphrase\t\(faces)\t\t1400"
        }
        try (table + rows.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("mac/takes.tsv"), atomically: true, encoding: .utf8)
        return try CharacterPack(directory: dir)
    }

    func rig(_ pack: CharacterPack, voice: AppSettings.Voice = .sounds, talk: Talk = .normal, remarks: Bool = false) -> InviteRig {
        let rig = InviteRig()
        rig.pack = pack
        rig.talk = talk
        if remarks {
            let normals = RemarksTests.kept
            rig.react.remarking = MomentOutput.Remarking(normals: { normals }, minutes: { Int($0 / 60_000) % 1440 })
        }
        rig.react.voice = { voice }
        return rig
    }

    static var check: Event { AsidesTests.check }
    func win() -> Facts { AsidesTests().win() }
    func tests(_ result: String, before: Int64, topic: String = "tests") -> Facts { AsidesTests().check(result, before: before, topic: topic) }

    /// What a run sent: each Moment's takes' ids and its sign.
    func played(_ rig: InviteRig) -> [String] {
        rig.sent.map { ($0.say?.takes.map(\.id).joined(separator: "+") ?? "-") + " | " + ($0.sign ?? "-") }
    }

    /// At a win in a bright face, a recorded sentence wins over the rows
    /// with none: the finish says it whole, and its aside behind it is
    /// that row's text.
    func testARecordedSentenceIsSaidAndShown() throws {
        try requirePack("boop")
        let rig = rig(try Self.voiced())
        let result = try XCTUnwrap(rig.run(AsidesTests.finish, win(), face: "proud"))
        let said = try XCTUnwrap(rig.sent.first?.say?.takes.first)
        XCTAssertEqual(said.part, .sentence)
        XCTAssertEqual(rig.sent.first?.say?.takes.count, 1, "said whole, no sound before it")
        let shown = try XCTUnwrap(rig.sent.last?.sign)
        let rows = ["win.all-yours": "Done! Buddygotchi, all yours.", "win.high-five": "High five! Buddygotchi, done."]
        XCTAssertEqual(rows[said.meaning], shown, "voice and text are one choice")
        XCTAssertEqual(result.facts["takes"], .array([.string(said.id)]))
    }

    /// Never the same sentence twice running, while another fits.
    func testNeverTheSameSentenceTwiceRunning() throws {
        try requirePack("boop")
        let rig = rig(try Self.voiced())
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
        for (face, facts, e) in [("calm", win(), AsidesTests.finish), ("grumpy", tests("ok", before: 2), Self.check),
                                 ("annoyed", tests("failed", before: 0, topic: "build"), Self.check)] {
            let voiced = rig(try Self.voiced()), plain = rig(.active)
            voiced.run(e, facts, face: face)
            plain.run(e, facts, face: face)
            XCTAssertEqual(played(voiced), played(plain), face)
            XCTAssertFalse(voiced.sent.flatMap { $0.say?.takes ?? [] }.contains { $0.part == .sentence }, face)
        }
    }

    /// A named check's sentence fits only that check; and a failed check,
    /// which has no skit, speaks only with a sentence.
    func testACheckSaysItsOwnSentence() throws {
        try requirePack("boop")
        let rig = rig(try Self.voiced())
        rig.run(Self.check, tests("failed", before: 0), face: "determined")
        XCTAssertEqual(rig.sent.first?.say?.takes.map(\.meaning), ["oops.tests"])
        XCTAssertEqual(rig.sent.first?.sign, "Uh oh. The tests failed.")
        XCTAssertEqual(rig.sent.first?.low, true)
        rig.sent = []
        rig.run(Self.check, tests("failed", before: 0, topic: "build"), face: "determined")
        XCTAssertEqual(rig.sent.first?.say?.takes ?? [], [], "the build's failure: text only")
        XCTAssertNotNil(rig.sent.first?.sign)
    }

    /// A remark whose line names a recorded sentence says it.
    func testARemarkSaysItsSentence() throws {
        try requirePack("boop")
        let rig = rig(try Self.voiced(), remarks: true)
        rig.run(RemarksTests.finish(), RemarksTests().win(minutes: 2), face: "happy")
        XCTAssertEqual(rig.sent.first?.say?.takes.map(\.meaning), ["win.quick"])
        XCTAssertEqual(rig.sent.last?.sign, "that was fast", "the remark's own text")
    }

    /// You back says its sentence; its sign stays as it was.
    func testBackSaysItsSentenceOnly() throws {
        try requirePack("boop")
        let voiced = rig(try Self.voiced()), plain = rig(.active)
        let facts: Facts = ["away_ms": .int(20 * 60_000), "away": .string(Band.away(ms: 20 * 60_000))]
        voiced.run(RemarksTests.cameBack(), facts, face: "happy")
        plain.run(RemarksTests.cameBack(), facts, face: "happy")
        XCTAssertEqual(voiced.sent.first?.say?.takes.map(\.meaning), ["back.youre-back"])
        XCTAssertEqual(voiced.sent.map(\.sign), plain.sent.map(\.sign))
    }

    /// Quiet, a call (the board keeps quiet) and swearing gate as ever;
    /// and speaking on the Mac, nothing changes: no sentence, the same text.
    func testTheGatesHold() throws {
        try requirePack("boop")
        let quiet = rig(try Self.voiced(), talk: .quiet)
        quiet.run(Self.check, tests("failed", before: 0), face: "determined")
        XCTAssertEqual(quiet.sent.first?.say?.takes ?? [], [])
        XCTAssertNil(quiet.sent.first?.sign)
        let call = rig(try Self.voiced())
        call.react = MomentOutput(queue: { m, _ in call.sent.append(m) }, blocked: { nil }, speaks: { false }, pack: call.pack,
                                  signs: RuntimeTests.steering.signs, line: { _ in Line("", facts: call.facts) })
        call.run(AsidesTests.finish, win(), face: "happy")
        XCTAssertTrue(call.sent.allSatisfy { $0.say?.takes.isEmpty ?? true }, "a board that doesn't speak says nothing")
        // No swear: the it-broke sentence, never a swear row's.
        let upset = rig(try Self.voiced())
        upset.run(AsidesTests.finish, AsidesTests().failed(), face: "sad")
        XCTAssertEqual(upset.sent.first?.say?.takes.map(\.meaning), ["upset.it-broke"])
        XCTAssertEqual(upset.sent.last?.sign, "Aw. Buddygotchi broke.")
        for voice in [AppSettings.Voice.speaks, .cloud] {
            let voiced = rig(try Self.voiced(), voice: voice), plain = rig(.active, voice: voice)
            voiced.run(AsidesTests.finish, win(), face: "happy")
            plain.run(AsidesTests.finish, win(), face: "happy")
            XCTAssertEqual(played(voiced), played(plain), "\(voice)")
            XCTAssertEqual(voiced.sent.map(\.aloud), plain.sent.map(\.aloud), "\(voice)")
        }
    }

    /// Jev's seat offers the sentences that fit, and its pick is said.
    func testJevPicksAmongTheSentences() throws {
        try requirePack("boop")
        let rig = rig(try Self.voiced())
        rig.facts = win()
        let asked = rig.react.questions(now: AsidesTests.finish, log: Transcript.log().view(now: AsidesTests.finish.at))
        let options = try XCTUnwrap(asked.first { $0.key == MomentOutput.takeKey }).options.map(\.name)
        XCTAssertEqual(Set(options), ["Done! All yours", "High five! Done"])
        for pick in options {
            rig.sent = []
            _ = rig.react.run([MomentOutput.emotionKey: Answer(choice: "happy", probabilities: ["happy": 1]),
                               MomentOutput.takeKey: Answer(choice: pick, probabilities: [pick: 1])],
                              now: AsidesTests.finish, log: Transcript.log().view(now: AsidesTests.finish.at))
            XCTAssertEqual(rig.sent.first?.say?.takes.map(\.text), [pick])
        }
    }
}
