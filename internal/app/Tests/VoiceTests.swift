import Foundation
import MellowHarness
import XCTest
@testable import BoopKit
import BoopDevKit

extension Take {
    /// A real take by id, for tests.
    static func named(_ id: String) -> Take { Take.all.first { $0.id == id }! }
}

extension Moment.Say {
    /// Excited's "Go" (new.d02): a real take for tests.
    static let go = Moment.Say(takes: [.named("new.d02")])

    /// A made-up take `ms` long, for tests that time a line.
    static func test(ms: Int) -> Moment.Say {
        .init(takes: [Take(id: "test", text: "Test", part: .about, meaning: "work", kind: .word, moods: ["calm"], finish: nil, ms: ms)])
    }
}

/// The recorded voice, Boop's pack's own (characters/CHARACTER.md §8).
final class VoiceTests: XCTestCase {
    override func setUpWithError() throws { try requireVoice() }

    let moods = CharacterPack.active.moods.map(\.id)

    /// Every take plays in moods the pack has, has a part and a meaning
    /// the voice keeps, and a length and text the bubble can show; ids are
    /// unique.
    func testEveryTakeIsUsable() {
        // The feelings and the topics the table keeps from before skits:
        // nothing but your hello and bye at a lock picks them now.
        let feelings: Set = ["upset", "glad", "tickled", "shaken"], topics: Set = ["retry", "work", "tests", "done", "quiet", "hello"]
        let skits = Set(CharacterPack.active.skits.map(\.id))
        // The voice file's takes that something says, each once as itself,
        // and a feeling's or topic's take again as each reply or skit it's
        // the words of. The takes of other topics stay on the card, and off
        // this table.
        XCTAssertEqual(Set(Take.all.map(\.id)).count, 1832)
        XCTAssertEqual(Set(Take.all.map { "\($0.id) \($0.part) \($0.meaning)" }).count, Take.all.count)
        let recorded = Dictionary(Take.all.filter { $0.part != .reply && $0.part != .skit }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let replies = Set(MomentOutput.replies.map(\.name) + ["dunno"])
        for t in Take.all {
            XCTAssertFalse(t.moods.isEmpty, t.id)
            XCTAssertTrue(Set(t.moods).isSubset(of: moods), "\(t.id) is in \(t.moods)")
            switch t.part {
            case .feeling: XCTAssertTrue(feelings.contains(t.meaning), "\(t.id) feels \(t.meaning)")
            case .about: XCTAssertTrue(topics.contains(t.meaning), "\(t.id) is about \(t.meaning)")
            case .skit:
                XCTAssertTrue(skits.contains(t.meaning), "\(t.id) is skit \(t.meaning), which the pack hasn't")
                if let own = recorded[t.id] {
                    XCTAssertTrue(own.text == t.text && own.kind == t.kind && own.moods == t.moods && own.ms == t.ms,
                                  "\(t.id) as a skit's is the recorded take")
                }
                XCTAssertNil(t.finish, "a skit's takes fit any finish: its rule says when it plays")
            case .reply:
                XCTAssertTrue(replies.contains(t.meaning), "\(t.id) replies \(t.meaning), which no reply is")
                if let own = recorded[t.id] {
                    XCTAssertTrue(own.text == t.text && own.kind == t.kind && own.moods == t.moods && own.ms == t.ms,
                                  "\(t.id) as a reply is the recorded take")
                }
                XCTAssertNil(t.finish, "a reply's words fit any finish")
                XCTAssertNotEqual(t.kind, .swear, "never a swear at you")
            }
            XCTAssertTrue((300...3000).contains(t.ms), "\(t.id) is \(t.ms) ms")
            XCTAssertTrue(!t.text.isEmpty && t.text.utf8.count <= 35 && t.text.allSatisfy { $0.isASCII }, t.text)
            XCTAssertTrue(t.finish == nil || ["success", "failure"].contains(t.finish!), t.id)
        }
        // Swears only on a failure, as a feeling, or as the upset skit's.
        XCTAssertTrue(Take.all.filter { $0.kind == .swear }.allSatisfy {
            $0.finish == "failure" && $0.part == .feeling || $0.part == .skit && $0.meaning == "upset"
        })
        XCTAssertEqual(Take.voiceVersion.count, 12)
    }

    /// Your hello and bye at a lock say the reply's own words, which every
    /// face of the pack has.
    func testEveryFaceCanWave() {
        for reply in ["hello", "bye"] {
            XCTAssertEqual(Set(Take.all.filter { $0.part == .reply && $0.meaning == reply }.flatMap(\.moods)), Set(moods), reply)
        }
    }

    /// The takes the board plays are the Mac's: voicegen writes both, and
    /// the board reports the pack's version.
    func testThePackHasEveryTake() throws {
        let pack = try Data(contentsOf: CharacterPack.active.directory.appendingPathComponent("voice/voice.bin"))
        XCTAssertEqual(pack.prefix(8), Data("BOOPVOX1".utf8))
        XCTAssertEqual(PackCheck.voiceFileVersion(pack), Take.voiceVersion, "rerun voicegen")
        func u32(_ at: Int) -> Int { pack[at..<at + 4].enumerated().reduce(0) { $0 | Int($1.1) << (8 * $1.0) } }
        let count = u32(24), size = u32(28), index = u32(32)
        let ids = (0..<count).map { i in String(decoding: pack[(index + i * size)...].prefix(72).prefix { $0 != 0 }, as: UTF8.self) }
        // The card keeps the takes of topics nothing says now: the
        // table is the ones something says, every one of them on the card.
        XCTAssertEqual(Set(Take.all.map(\.id)).subtracting(ids), [], "every take the Mac may ask for is one the board has")
    }

    /// A take of the answer, in the face's mood only, fit for
    /// the finish.
    func testATakeIsOnlyEverTheFacesMood() {
        var rng = SplitMix64(seed: 1)
        for face in moods {
            for (part, answers) in [(Take.Part.feeling, Voice.answers(.feeling)), (.about, Voice.answers(.about)), (.reply, Voice.answers(.reply)),
                                    (.skit, Voice.answers(.skit))] {
                for a in answers {
                    for kind in Take.Kind.allCases {
                        for finish in [nil, "success", "failure"] {
                            guard let t = Voice.take(part, meaning: a, kind: kind, face: face, finish: finish, rng: &rng) else { continue }
                            XCTAssertTrue(t.moods.contains(face))
                            XCTAssertEqual(t.meaning, a)
                            XCTAssertEqual(t.part, part)
                            XCTAssertTrue(t.finish == nil || t.finish == finish, "\(t.id) needs a \(t.finish!)")
                            XCTAssertTrue(t.kind != .swear || kind == .swear, "\(t.id): a swear nobody asked for")
                        }
                    }
                }
            }
        }
    }

    /// A success take only on a success, a swear only on a
    /// failed turn.
    func testTheFinishGatesSuccessesAndSwears() {
        var rng = SplitMix64(seed: 2)
        // Grumpy is glad only with relief, at a success.
        XCTAssertNil(Voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: nil, rng: &rng))
        XCTAssertEqual(Voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: "success", rng: &rng)?.finish, "success")
        // Grumpy swears at a failed turn; with no failure, the nearest
        // plainer kind: a phrase.
        XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .swear, face: "grumpy", finish: "failure", rng: &rng)?.kind, .swear)
        XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .swear, face: "grumpy", finish: nil, rng: &rng)?.kind, .phrase)
        // "Passed" is about tests, and only at a success; or the fix
        // skit's, which plays only at a check passing again.
        XCTAssertFalse(Take.all.contains { $0.text == "Passed" && ($0.meaning != "tests" || $0.finish != "success") && $0.meaning != "fix" })
    }

    /// With none of the kind asked for, the nearest kind,
    /// plainer first; never a swear nobody asked for.
    func testKindTakesTheNearest() {
        XCTAssertEqual(Voice.order(.sound), [.sound, .word, .phrase])
        XCTAssertEqual(Voice.order(.word), [.word, .sound, .phrase])
        XCTAssertEqual(Voice.order(.phrase), [.phrase, .word, .sound])
        XCTAssertEqual(Voice.order(.swear), [.swear, .phrase, .word, .sound])
        var rng = SplitMix64(seed: 3)
        // Tickled has no sounds: a sound asked for says a word.
        XCTAssertEqual(Voice.take(.feeling, meaning: "tickled", kind: .sound, face: "calm", finish: nil, rng: &rng)?.kind, .word)
        // Happy's glad words need a success: without one, a sound.
        XCTAssertEqual(Voice.take(.feeling, meaning: "glad", kind: .word, face: "happy", finish: nil, rng: &rng)?.kind, .sound)
    }

    /// The last line's words aren't said again while another
    /// fits.
    func testTheLastTakesArentRepeated() {
        var rng = SplitMix64(seed: 4)
        let sounds = Take.all.filter { $0.part == .feeling && $0.meaning == "upset" && $0.moods.contains("annoyed") && $0.kind == .sound }
        let avoiding = sounds.dropLast().map(\.text)
        for _ in 0..<50 {
            XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil, avoiding: avoiding, rng: &rng)?.id,
                           sounds.last?.id)
        }
        // With every one avoided, one is said anyway.
        XCTAssertNotNil(Voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil,
                                   avoiding: sounds.map(\.text), rng: &rng))
        // A word recorded twice (previous.basta and phase1.borrowed.basta__annoyed__contained)
        // isn't said again by its other recording.
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.feeling, meaning: "upset", kind: .word, face: "annoyed", finish: nil,
                                         avoiding: [Take.named("previous.basta").text], rng: &rng)?.text, "Basta")
        }
        // Nor by another mood's: after calm's "Ready", a curious face
        // doesn't say its own.
        let ready = Take.named("phase1.word.begin.ready__calm__contained")
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.about, meaning: "work", kind: .word, face: "curious", finish: nil,
                                         avoiding: [ready.text], rng: &rng)?.text, "Ready")
        }
    }

    /// What Boop says is one take, as big as the moment: a sound when
    /// it's small, a word medium, a phrase big.
    func testWhatItSaysIsOneTakeAsBigAsTheMoment() {
        XCTAssertEqual(MomentOutput.sizes.map(\.loops), [1, 2, 3], "small to big hold once to three times")
        XCTAssertEqual(MomentOutput.sizes.map(\.kind), [.sound, .word, .phrase])
        XCTAssertEqual(MomentOutput.size(loops: nil).name, "small", "no hold is a small moment")
        XCTAssertEqual(MomentOutput.size(loops: 3).name, "big")
        var rng = SplitMix64(seed: 5)
        // A phrase asked for is a topic's too: "Fingers crossed".
        XCTAssertEqual(Voice.take(.about, meaning: "tests", kind: .phrase, face: "curious", finish: nil, rng: &rng)?.kind, .phrase)
    }

    /// A word or a swear gets a sound before it about half the time
    /// (`Voice.leadChance`): the same meaning, performed in the same mood,
    /// in the face's, within `maxSayMs` with the board's gap. Never before
    /// a sound or a phrase.
    func testAWordMayGetASoundOfTheSame() throws {
        let player = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../firmware/src/voice/player.h").standardizedFileURL, encoding: .utf8)
        XCTAssertEqual(player.firstMatch(of: /kJoinGapMs = (\d+);/).flatMap { Int($0.1) }, Voice.joinGapMs, "the board's gap")
        XCTAssertEqual(Voice.leadChance, 50)
        var rng = SplitMix64(seed: 6)
        var led = 0, tries = 0
        for face in moods {
            for word in Take.all where (word.kind == .word || word.kind == .swear) && word.moods.contains(face) {
                guard let lead = Voice.lead(before: word, face: face, finish: word.finish, rng: &rng) else { continue }
                XCTAssertEqual(lead.kind, .sound)
                XCTAssertEqual(lead.part, word.part)
                XCTAssertEqual(lead.meaning, word.meaning, "\(lead.id) before \(word.id): one thing said")
                XCTAssertEqual(lead.moods.first, word.moods.first, "performed in the same mood")
                XCTAssertTrue(lead.moods.contains(face))
                XCTAssertLessThanOrEqual(lead.ms + Voice.joinGapMs + word.ms, Voice.maxSayMs)
            }
        }
        // About half of grumpy's upset words, whose sounds fit.
        let grumpy = try XCTUnwrap(Take.all.first { $0.meaning == "upset" && $0.kind == .word && $0.moods.first == "grumpy" && $0.finish == nil })
        for _ in 0..<400 {
            tries += 1
            if Voice.lead(before: grumpy, face: "grumpy", finish: nil, rng: &rng) != nil { led += 1 }
        }
        XCTAssertTrue((140...260).contains(led), "\(led) of \(tries)")
        for t in Take.all where t.kind == .sound || t.kind == .phrase {
            XCTAssertNil(Voice.lead(before: t, face: t.moods[0], finish: t.finish, rng: &rng), t.id)
        }
    }

    /// Every placeholder take, spoken until it's recorded for real, is on
    /// the voice bank's list to record (`plans/regenerate.json`, which
    /// voicegen's placeholders.py keeps), and only those: the list is
    /// exactly what to regenerate.
    func testEveryPlaceholderIsListedToRecord() throws {
        let list = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../characters/boop/design/assets/boop-voice-v1/plans/regenerate.json").standardizedFileURL
        let slots = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: list)) as? [String: Any])["slots"] as? [[String: Any]]
        let listed = Set(try XCTUnwrap(slots).compactMap { $0["take"] as? String })
        let placeholders = Set(Take.all.map(\.id).filter { $0.hasPrefix("placeholder.") })
        XCTAssertFalse(placeholders.isEmpty)
        XCTAssertEqual(placeholders, listed, "rerun placeholders.py, then voicegen")
    }

    /// Two takes on the wire, as the board still takes them.
    func testTwoTakesOnTheWire() {
        let two = Moment.Say(takes: [.named("previous.tsk"), .named("phase1.word.test.test__annoyed__contained")])
        XCTAssertEqual(two.json.json, #"{"take":"previous.tsk","then":"phase1.word.test.test__annoyed__contained"}"#)
        XCTAssertEqual(two.text, "Tsk... Test")
    }
}
