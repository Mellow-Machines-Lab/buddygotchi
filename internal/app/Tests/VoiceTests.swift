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
    /// Proud's "Done" (word.success.done__happy), the win skit's: a real
    /// take for tests.
    static let done = Moment.Say(takes: [.named("word.success.done__happy")])

    /// A made-up take `ms` long, for tests that time a line.
    static func test(ms: Int) -> Moment.Say {
        .init(takes: [Take(id: "test", text: "Test", part: .skit, meaning: "win", kind: .word, moods: ["calm"], ms: ms)])
    }
}

/// The recorded voice, Boop's pack's own (characters/CHARACTER.md §8).
final class VoiceTests: XCTestCase {
    override func setUpWithError() throws { try requireVoice() }

    /// The faces that speak: the pack's, and the meme faces a skit may
    /// show (`RulesBrain.meme`), which the voice bank's deliveries name
    /// too. Deadpan and side-eye come where nothing speaks.
    let moods = CharacterPack.active.moods.map(\.id) + ["smug", "silent_scream", "faint"]

    /// Every take plays in moods the pack has, is a reply's or a skit's
    /// the pack has, and has a length and text the bubble can show; a take
    /// listed for several is the one recorded take each time.
    func testEveryTakeIsUsable() {
        let skits = Set(CharacterPack.active.skits.map(\.id))
        // The voice file's takes, each listed once for each reply, skit or
        // sentence it's the words of.
        XCTAssertEqual(Set(Take.all.map(\.id)).count, 500)
        XCTAssertEqual(Set(Take.all.map { "\($0.id) \($0.part) \($0.meaning)" }).count, Take.all.count)
        let recorded = Dictionary(Take.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let replies = Set(MomentOutput.replies.map(\.name) + ["dunno"])
        let sentences = Set(RuntimeTests.steering.signs.compactMap(\.take))
        for t in Take.all {
            XCTAssertFalse(t.moods.isEmpty, t.id)
            XCTAssertTrue(Set(t.moods).isSubset(of: moods), "\(t.id) is in \(t.moods)")
            if let own = recorded[t.id] {
                XCTAssertTrue(own.text == t.text && own.kind == t.kind && own.moods == t.moods && own.ms == t.ms,
                              "\(t.id) as \(t.part) \(t.meaning) is the recorded take")
            }
            switch t.part {
            case .skit:
                XCTAssertTrue(skits.contains(t.meaning), "\(t.id) is skit \(t.meaning), which the pack hasn't")
            case .reply:
                XCTAssertTrue(replies.contains(t.meaning), "\(t.id) replies \(t.meaning), which no reply is")
                XCTAssertNotEqual(t.kind, .swear, "never a swear at you")
            case .sentence:
                XCTAssertTrue(sentences.contains(t.meaning), "\(t.id) says sentence \(t.meaning), which no line of signs.md names")
            }
            // A sentence, said whole, may run a little longer than a word.
            XCTAssertTrue((300...(t.part == .sentence ? 3500 : 3000)).contains(t.ms), "\(t.id) is \(t.ms) ms")
            XCTAssertTrue(!t.text.isEmpty && t.text.utf8.count <= 35 && t.text.allSatisfy { $0.isASCII }, t.text)
        }
        // Swears only as the upset skit's.
        XCTAssertEqual(Set(Take.all.filter { $0.kind == .swear && $0.part != .sentence }.map { "\($0.part) \($0.meaning)" }), ["skit upset"])
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
        XCTAssertEqual(Set(Take.all.map(\.id)), Set(ids), "the board has every take the Mac may ask for, and only those")
    }

    /// A take of the answer, in the face's mood only.
    func testATakeIsOnlyEverTheFacesMood() {
        var rng = SplitMix64(seed: 1)
        for face in moods {
            for part in Take.Part.allCases {
                for a in Set(Take.all.filter { $0.part == part }.map(\.meaning)) {
                    for kind in Take.Kind.allCases {
                        guard let t = Voice.take(part, meaning: a, kind: kind, face: face, rng: &rng) else { continue }
                        XCTAssertTrue(t.moods.contains(face))
                        XCTAssertEqual(t.meaning, a)
                        XCTAssertEqual(t.part, part)
                        XCTAssertTrue(t.kind != .swear || kind == .swear, "\(t.id): a swear nobody asked for")
                    }
                }
            }
        }
    }

    /// The table's finish column is empty in every row: no take needs a
    /// finish, and Voice reads none. "Passed" is only the fix skit's, which
    /// plays only at a check passing again.
    func testNoTakeNeedsAFinish() throws {
        let table = try String(contentsOf: CharacterPack.active.directory.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)
        let rows = table.split(separator: "\n").filter { !$0.hasPrefix("#") }.dropFirst()
        XCTAssertEqual(rows.count, Take.all.count)
        for row in rows { XCTAssertEqual(row.split(separator: "\t", omittingEmptySubsequences: false)[6], "", String(row)) }
        XCTAssertEqual(Set(Take.all.filter { $0.text == "Passed" }.map { "\($0.part) \($0.meaning)" }), ["skit fix"])
    }

    /// With none of the kind asked for, the nearest kind,
    /// plainer first; never a swear nobody asked for.
    func testKindTakesTheNearest() {
        XCTAssertEqual(Voice.order(.sound), [.sound, .word, .phrase])
        XCTAssertEqual(Voice.order(.word), [.word, .sound, .phrase])
        XCTAssertEqual(Voice.order(.phrase), [.phrase, .word, .sound])
        XCTAssertEqual(Voice.order(.swear), [.swear, .phrase, .word, .sound])
        var rng = SplitMix64(seed: 3)
        // The win skit has no sound: a sound asked for says a word.
        XCTAssertEqual(Voice.take(.skit, meaning: "win", kind: .sound, face: "calm", rng: &rng)?.kind, .word)
    }

    /// The last line's words aren't said again while another
    /// fits.
    func testTheLastTakesArentRepeated() {
        var rng = SplitMix64(seed: 4)
        let sounds = Take.all.filter { $0.part == .skit && $0.meaning == "fix" && $0.moods.contains("annoyed") && $0.kind == .sound }
        XCTAssertGreaterThan(sounds.count, 1)
        let avoiding = sounds.dropLast().map(\.text)
        for _ in 0..<50 {
            XCTAssertEqual(Voice.take(.skit, meaning: "fix", kind: .sound, face: "annoyed", avoiding: avoiding, rng: &rng)?.id,
                           sounds.last?.id)
        }
        // With every one avoided, one is said anyway.
        XCTAssertNotNil(Voice.take(.skit, meaning: "fix", kind: .sound, face: "annoyed",
                                   avoiding: sounds.map(\.text), rng: &rng))
        // A word isn't said again by its take in another delivery: after
        // the flat "Basta", an annoyed face doesn't say its glum one.
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.reply, meaning: "no", kind: .word, face: "annoyed",
                                         avoiding: [Take.named("borrowed.basta__calm").text], rng: &rng)?.text, "Basta")
        }
        // Nor in a bright face: after the flat "Yes", a happy face doesn't
        // say its bright one.
        let yes = Take.named("word.talk-yes.yes__calm")
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.reply, meaning: "yes", kind: .word, face: "happy",
                                         avoiding: [yes.text], rng: &rng)?.text, "Yes")
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
        // A phrase asked for is a skit's too: "Nailed it".
        XCTAssertEqual(Voice.take(.skit, meaning: "win", kind: .phrase, face: "happy", rng: &rng)?.kind, .phrase)
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
                guard let lead = Voice.lead(before: word, face: face, rng: &rng) else { continue }
                XCTAssertEqual(lead.kind, .sound)
                XCTAssertEqual(lead.part, word.part)
                XCTAssertEqual(lead.meaning, word.meaning, "\(lead.id) before \(word.id): one thing said")
                XCTAssertEqual(lead.moods.first, word.moods.first, "performed in the same mood")
                XCTAssertTrue(lead.moods.contains(face))
                XCTAssertLessThanOrEqual(lead.ms + Voice.joinGapMs + word.ms, Voice.maxSayMs)
            }
        }
        // About half of calm's fix words, whose sounds fit: "Phew... Fixed".
        let calm = try XCTUnwrap(Take.all.first { $0.part == .skit && $0.meaning == "fix" && $0.kind == .word && $0.moods.first == "calm" })
        for _ in 0..<400 {
            tries += 1
            if Voice.lead(before: calm, face: "calm", rng: &rng) != nil { led += 1 }
        }
        XCTAssertTrue((140...260).contains(led), "\(led) of \(tries)")
        for t in Take.all where t.kind == .sound || t.kind == .phrase {
            XCTAssertNil(Voice.lead(before: t, face: t.moods[0], rng: &rng), t.id)
        }
    }

    /// Two takes on the wire, as the board still takes them.
    func testTwoTakesOnTheWire() {
        let two = Moment.Say(takes: [.named("nonverbal.frustration.tsk__sad"), .named("borrowed.basta__sad")])
        XCTAssertEqual(two.json.json, #"{"take":"nonverbal.frustration.tsk__sad","then":"borrowed.basta__sad"}"#)
        XCTAssertEqual(two.text, "Tsk... Basta")
    }
}
