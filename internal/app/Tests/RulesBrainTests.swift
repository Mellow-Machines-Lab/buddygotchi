import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The mood map as rules (`MoodMap`): each move one of the pack's mood
/// files names, one test a mood, so a change to the map shows here.
final class MoodMapTests: XCTestCase {
    typealias Cue = MoodMap.Cue

    func move(_ from: String, _ cues: Cue..., level: Int = 1) -> String? { MoodMap.move(from: from, cues: Set(cues), level: level) }

    /// Every mood the map moves from or to is one of the pack's seven, and
    /// each of the seven has its moves.
    func testTheMapIsThePacksSevenMoods() {
        let moods = Set(CharacterPack.active.lasting.map(\.id))
        XCTAssertEqual(moods, ["calm", "happy", "focused", "proud", "cross", "sad", "lonely"])
        for m in MoodMap.moves {
            XCTAssertTrue(moods.contains(m.from), m.from)
            XCTAssertTrue(moods.contains(m.to), m.to)
        }
        XCTAssertEqual(Set(MoodMap.moves.map(\.from)), moods)
    }

    /// An event no row names leaves the mood where it is.
    func testWhatNoRowNamesKeepsTheMood() {
        XCTAssertNil(move("calm", .touched), "a single poke: calm stays calm")
        XCTAssertNil(move("calm", .turnDone), "a plain finish")
        XCTAssertNil(move("proud", .checkFailed), "the pride holds through a failed check")
        XCTAssertNil(move("focused", .checkFailed, .frustrated), "focused stays through failures and frustration")
        XCTAssertNil(move("sad", .turnDone), "sad stays through routine turns")
        XCTAssertNil(move("sad", .twoPokes), "two pokes don't make sad cross: it takes 3+")
    }

    /// calm.md: kind words, a long turn done, thanks or you back, happy; a
    /// long turn working on or frustration, focused; a check fixed, proud;
    /// a failed check or turn, 2 pokes or hush, cross; a very long turn
    /// failing, giving up, sad news or rude words, sad; back after 20 to
    /// 40 hours, lonely.
    func testCalm() {
        for c: Cue in [.kindWords, .longDone, .thanks, .back] { XCTAssertEqual(move("calm", c), "happy", c.rawValue) }
        for c: Cue in [.longWorking, .frustrated] { XCTAssertEqual(move("calm", c), "focused", c.rawValue) }
        XCTAssertEqual(move("calm", .checkFixed), "proud")
        for c: Cue in [.checkFailed, .turnFailed, .twoPokes, .hush] { XCTAssertEqual(move("calm", c), "cross", c.rawValue) }
        for c: Cue in [.veryLongFailed, .gaveUp, .sadNews, .rudeWords] { XCTAssertEqual(move("calm", c), "sad", c.rawValue) }
        XCTAssertEqual(move("calm", .backAfterADay, .back), "lonely", "missing you wins over a plain hello")
    }

    /// happy.md: a check fixed or a long turn done, proud; a long turn or
    /// frustration, focused; a failed check or turn or 2 pokes, cross; the
    /// sad four, sad.
    func testHappy() {
        for c: Cue in [.checkFixed, .longDone] { XCTAssertEqual(move("happy", c), "proud", c.rawValue) }
        for c: Cue in [.longWorking, .frustrated] { XCTAssertEqual(move("happy", c), "focused", c.rawValue) }
        for c: Cue in [.checkFailed, .turnFailed, .twoPokes] { XCTAssertEqual(move("happy", c), "cross", c.rawValue) }
        for c: Cue in [.veryLongFailed, .gaveUp, .sadNews, .rudeWords] { XCTAssertEqual(move("happy", c), "sad", c.rawValue) }
        XCTAssertNil(move("happy", .thanks), "stays happy through thanks")
    }

    /// focused.md: a check fixed or a long turn done, proud; kind words,
    /// thanks or a very long turn done, happy; a failed turn or 2 pokes,
    /// cross; a very long turn failing, giving up or sad news, sad.
    func testFocused() {
        XCTAssertEqual(move("focused", .checkFixed), "proud")
        XCTAssertEqual(move("focused", .turnDone, .longDone), "proud")
        XCTAssertEqual(move("focused", .turnDone, .longDone, .veryLongDone), "proud", "a long turn's hard work done comes first")
        for c: Cue in [.kindWords, .thanks, .veryLongDone] { XCTAssertEqual(move("focused", c), "happy", c.rawValue) }
        for c: Cue in [.turnFailed, .twoPokes] { XCTAssertEqual(move("focused", c), "cross", c.rawValue) }
        for c: Cue in [.veryLongFailed, .gaveUp, .sadNews] { XCTAssertEqual(move("focused", c), "sad", c.rawValue) }
    }

    /// proud.md: frustration, focused; 2 pokes or a failed turn, cross; a
    /// very long turn failing, sad news or rude words, sad. It fades into
    /// happy by itself, which is code's.
    func testProud() {
        XCTAssertEqual(move("proud", .frustrated), "focused")
        for c: Cue in [.twoPokes, .turnFailed] { XCTAssertEqual(move("proud", c), "cross", c.rawValue) }
        for c: Cue in [.veryLongFailed, .sadNews, .rudeWords] { XCTAssertEqual(move("proud", c), "sad", c.rawValue) }
    }

    /// cross.md: sorry or thanks, calm, at once; a stroke while only
    /// annoyed, calm, but not at grumpy or angry; a check failing on or
    /// frustration, focused; a check fixed or a turn done, calm; the sad
    /// four, sad.
    func testCross() {
        for c: Cue in [.sorry, .thanks] { XCTAssertEqual(move("cross", c, level: 3), "calm", c.rawValue) }
        XCTAssertEqual(move("cross", .stroke, level: 1), "calm", "annoyed: a stroke ends it")
        XCTAssertNil(move("cross", .stroke, level: 2), "grumpy: a stroke only softens a level, code's")
        for c: Cue in [.checkFailed, .frustrated] { XCTAssertEqual(move("cross", c), "focused", c.rawValue) }
        for c: Cue in [.checkFixed, .turnDone] { XCTAssertEqual(move("cross", c), "calm", c.rawValue) }
        for c: Cue in [.gaveUp, .veryLongFailed, .sadNews, .rudeWords] { XCTAssertEqual(move("cross", c), "sad", c.rawValue) }
        XCTAssertNil(move("cross", .twoPokes, .threePokes), "stays cross through more pokes")
    }

    /// sad.md: sorry, cheering up or thanks, happy; a stroke or a check
    /// fixed, calm; 3+ pokes, cross.
    func testSad() {
        for c: Cue in [.sorry, .kindWords, .thanks] { XCTAssertEqual(move("sad", c), "happy", c.rawValue) }
        for c: Cue in [.stroke, .checkFixed] { XCTAssertEqual(move("sad", c), "calm", c.rawValue) }
        XCTAssertEqual(move("sad", .twoPokes, .threePokes), "cross")
    }

    /// lonely.md: anything you do ends it: a stroke, a poke or a word,
    /// calm; praise or love, happy; an agent starting work, calm; a very
    /// long turn failing or giving up, sad.
    func testLonely() {
        for c: Cue in [.stroke, .touched, .agentStarts] { XCTAssertEqual(move("lonely", c), "calm", c.rawValue) }
        XCTAssertEqual(move("lonely", .kindWords, .touched), "happy")
        for c: Cue in [.veryLongFailed, .gaveUp] { XCTAssertEqual(move("lonely", c), "sad", c.rawValue) }
    }
}

/// The brain in the box (`RulesBrain`): what it reads of an event, and how
/// it answers the questions Jev is asked.
final class RulesBrainTests: XCTestCase {
    typealias Facts = [String: JSONValue]

    func event(_ type: Event.Kind, _ phase: Event.Phase? = nil, _ specific: String = "", data: Facts = [:], seq: Int = 1) -> Event {
        var e = Event(at: 0, source: .claude, type: type, phase: phase, specificType: specific, data: data)
        e.seq = seq
        return e
    }

    func finish(_ outcome: String = "done", length: String = "short", kind: String? = nil, tools: Int64 = 3) -> Facts {
        var f: Facts = ["outcome": .string(outcome), "length": .string(length), "tools": .int(tools),
                        "length_ms": .int(length == "very long" ? 600_000 : length == "long" ? 120_000 : 30_000)]
        if let kind { f["message"] = .object(["kind": .string(kind)]) }
        return f
    }

    func read(_ e: Event, _ f: Facts = [:]) -> RulesBrain.Read { RulesBrain.read(e, facts: f) }

    func testItReadsFinishes() {
        let end = event(.turn, .end, "Stop")
        XCTAssertEqual(read(end, finish(length: "long")).slot, .doneLong)
        XCTAssertEqual(read(end, finish(length: "long")).cues, [.turnDone, .longDone])
        XCTAssertEqual(read(end, finish(length: "very long")).cues, [.turnDone, .longDone, .veryLongDone])
        XCTAssertEqual(read(end, finish("failed")).cues, [.turnFailed])
        XCTAssertEqual(read(end, finish("failed", length: "very long")).cues, [.veryLongFailed])
        XCTAssertEqual(read(end, finish(kind: "stuck")).cues, [.gaveUp], "done, but it says it couldn't finish")
        XCTAssertEqual(read(end, finish(kind: "question")).slot, .chat)
    }

    func testItReadsChecksPokesAndComingBack() {
        let tool = event(.tool, .end, "PostToolUse")
        XCTAssertEqual(read(tool, ["topic": "tests", "result": "failed", "failed_before": 0]).slot, .checkFailed)
        XCTAssertEqual(read(tool, ["topic": "tests", "result": "failed", "failed_before": 2]).slot, .checkFailing)
        XCTAssertEqual(read(tool, ["topic": "tests", "result": "passed", "failed_before": 1]).cues, [.checkFixed])
        let poke = event(.poke)
        XCTAssertEqual(read(poke, ["in_a_row": 1]).cues, [.touched])
        XCTAssertEqual(read(poke, ["in_a_row": 2]).cues, [.touched, .twoPokes])
        XCTAssertEqual(read(poke, ["in_a_row": 3]).cues, [.touched, .twoPokes, .threePokes])
        let back = event(.presence, .end)
        XCTAssertEqual(read(back, ["away_ms": .int(3_600_000)]).cues, [.back])
        XCTAssertEqual(read(back, ["away_ms": .int(25 * 3_600_000)]).cues, [.backAfterADay, .back])
    }

    /// Your words, by plain matching, and the reply each gets.
    func testItReadsYourWords() {
        func words(_ s: String) -> RulesBrain.Read { RulesBrain.Words.read(s) }
        XCTAssertEqual(words("sorry buddy").reply, "thanks")
        XCTAssertTrue(words("sorry buddy").cues.contains(.sorry))
        XCTAssertEqual(words("you're so stupid").reply, "ouch")
        XCTAssertTrue(words("you're so stupid").cues.contains(.rudeWords))
        XCTAssertEqual(words("i've been pretty sad").reply, "comfort")
        XCTAssertEqual(words("how is claude doing").reply, "status")
        XCTAssertEqual(words("hello how are you").reply, "hello")
        XCTAssertEqual(words("good night boop").reply, "bye")
        XCTAssertEqual(words("roll over").reply, "no")
        XCTAssertEqual(words("shh").reply, "hush")
        XCTAssertEqual(words("the weather is purple").reply, "huh")
    }

    func brain(mood: String = "calm", level: Int = 1, facts: Facts) -> RulesBrain {
        RulesBrain(seed: 7, facts: { _ in facts }, mood: { _ in (mood, level) })
    }

    func answers(_ b: RulesBrain, _ e: Event, _ questions: [Question]) async throws -> Answers {
        try await b.reading(now: e, log: Log().view(now: 0)).answer(state: "", questions: questions, deadline: .seconds(1))
    }

    func question(_ key: String, _ names: [String]) -> Question {
        Question(key: key, text: "?", about: "the NOW section", judgeBy: "x", options: names.map { Option($0, $0) })
    }

    var faces: [String] { ["none"] + CharacterPack.active.faces.map(\.name) }

    /// A failed turn never gets a proud or happy face, in any mood.
    func testAFailedTurnIsNeverProud() async throws {
        for mood in ["calm", "happy", "focused", "proud", "cross", "sad"] {
            for _ in 0..<5 {
                let b = brain(mood: mood, facts: finish("failed", length: "long"))
                let a = try await answers(b, event(.turn, .end, "Stop"), [question(MomentOutput.emotionKey, faces)])
                let face = try XCTUnwrap(a[MomentOutput.emotionKey]?.choice)
                XCTAssertFalse(["proud", "happy", "excited", "pleased"].contains(face), "\(mood): \(face)")
            }
        }
    }

    /// The mood question: a move the map names when it's offered, else stay.
    func testTheMoodFollowsTheMap() async throws {
        let moods = ["calm", "happy", "focused", "proud", "cross", "sad"]
        let a = try await answers(brain(mood: "calm", facts: finish(length: "long")), event(.turn, .end, "Stop"), [question("mood", moods)])
        XCTAssertEqual(a["mood"]?.choice, "happy", "calm: a long turn's hard work done, happy")
        let b = try await answers(brain(mood: "calm", facts: finish()), event(.turn, .end, "Stop"), [question("mood", moods)])
        XCTAssertEqual(b["mood"]?.choice, "calm", "a plain finish: stay")
        let c = try await answers(brain(mood: "calm", facts: ["away_ms": .int(25 * 3_600_000)]), event(.presence, .end),
                                  [question("mood", moods)])
        XCTAssertEqual(c["mood"]?.choice, "happy", "lonely not offered: the next move, you back, happy")
    }

    /// Never the same face twice running for a slot while another fits.
    func testFacesDontRepeat() async throws {
        let b = brain(facts: finish(length: "short"))
        var last: String?
        for _ in 0..<12 {
            let a = try await answers(b, event(.turn, .end, "Stop"), [question(MomentOutput.emotionKey, faces)])
            let face = a[MomentOutput.emotionKey]?.choice
            XCTAssertNotEqual(face, last)
            last = face
        }
    }

    /// Every answer is one of its question's options, at 1.
    func testAnswersAreOptions() async throws {
        let qs = [question(MomentOutput.emotionKey, ["none", "calm"]), question(MomentOutput.replyKey, ["huh", "yes"]),
                  question("mood", ["calm", "happy"]), question(Signs.questionKey, ["none", "yay!"]), question("other", ["a", "b"])]
        let a = try await answers(brain(facts: finish(length: "long")), event(.turn, .end, "Stop"), qs)
        for q in qs {
            let pick = try XCTUnwrap(a[q.key])
            XCTAssertTrue(q.options.map(\.name).contains(pick.choice), q.key)
            XCTAssertEqual(pick.p, 1)
        }
    }

    /// A reply's sign is one of the lines for the reply it makes; a status
    /// reply holds up the agents' facts.
    func testAReplysSignFitsTheReply() async throws {
        let sign = Question(key: Signs.questionKey, text: "?", about: "x", judgeBy: "x",
                            options: [Option("facts", "With a status reply."), Option("hi!", "With a hello reply."),
                                      Option("nope", "With a no reply.")])
        let said = event(.said, data: ["words": "hello there"])
        let a = try await answers(brain(facts: ["words": "hello there"]), said, [sign])
        XCTAssertEqual(a[Signs.questionKey]?.choice, "hi!")
        let s = try await answers(brain(facts: ["words": "is claude done"]), event(.said, data: ["words": "is claude done"]), [sign])
        XCTAssertEqual(s[Signs.questionKey]?.choice, "facts")
    }

    /// The idle beat is held up, unless the mood is cross or low.
    func testTheIdleBeatWaitsOutCrossAndSad() async throws {
        let beat = question(Signs.questionKey, ["none", "fav snack?"])
        let checkIn = event(.checkIn, nil, "check_in")
        let calm = try await answers(brain(mood: "calm", facts: [:]), checkIn, [beat])
        XCTAssertEqual(calm[Signs.questionKey]?.choice, "fav snack?")
        let cross = try await answers(brain(mood: "cross", facts: [:]), checkIn, [beat])
        XCTAssertEqual(cross[Signs.questionKey]?.choice, "none")
    }

    /// The meme faces, each at its one rare moment (`RulesBrain.meme`), and
    /// none at the moments beside them: the 1st failed check, the 4th, a
    /// plain finish, a failed turn after one failed check.
    func testTheMemeFacesHaveTheirMoments() {
        func meme(_ e: Event, _ f: Facts, mood: String? = nil) -> String? { RulesBrain.meme(read(e, f), facts: f, mood: mood) }
        let tool = event(.tool, .end, "PostToolUse"), end = event(.turn, .end, "Stop")
        func check(_ result: String, before: Int64) -> Facts { ["topic": "tests", "result": .string(result), "failed_before": .int(before)] }
        func after(_ f: Facts, checks: Int64) -> Facts { f.merging(["checks_failed": .int(checks)]) { _, new in new } }
        XCTAssertNil(meme(tool, check("failed", before: 0)))
        XCTAssertEqual(meme(tool, check("failed", before: 1)), "deadpan", "the 2nd failed check in a row")
        XCTAssertEqual(meme(tool, check("failed", before: 2)), "silent_scream", "the 3rd, as the upset skit swears")
        XCTAssertNil(meme(tool, check("failed", before: 3)))
        XCTAssertEqual(meme(tool, ["tool": "shell", "result": "failed", "failing": 3]), "side_eye", "calls failing in a row")
        XCTAssertEqual(read(tool, ["tool": "shell", "result": "failed", "failing": 3]).slot, .failing)
        XCTAssertEqual(meme(tool, check("ok", before: 2)), "smug", "a check passing after it failed")
        XCTAssertEqual(meme(end, after(finish(length: "long"), checks: 1)), "smug", "a hard-won win")
        XCTAssertNil(meme(end, finish(length: "long")))
        XCTAssertNil(meme(end, after(finish("failed"), checks: 1)))
        XCTAssertEqual(meme(end, after(finish("failed"), checks: 2)), "silent_scream", "failures piled up")
        XCTAssertEqual(meme(end, finish("failed", length: "very long")), "faint")
        XCTAssertEqual(meme(end, after(finish("failed", length: "very long"), checks: 3)), "faint", "a very long turn faints first")
        XCTAssertEqual(meme(end, finish(kind: "stuck")), "faint", "the agent gave up")
        XCTAssertNil(meme(tool, check("ok", before: 1), mood: "sad"), "sad is never smug")
        XCTAssertEqual(meme(tool, check("ok", before: 1), mood: "cross"), "smug", "cross may be: it knew it")
        XCTAssertEqual(Set(CharacterPack.active.boardFaces.map(\.id)).subtracting(["squint"]),
                       ["deadpan", "side_eye", "smug", "silent_scream", "faint"], "every meme face but squint has a moment")
    }

    /// The rules show the meme face where it's offered, never twice
    /// running; offered nothing past the 18, they keep to the slot's faces.
    func testTheRulesShowAMemeFace() async throws {
        let tool = event(.tool, .end, "PostToolUse")
        let second: Facts = ["topic": "tests", "result": "failed", "failed_before": 1]
        let b = brain(facts: second)
        let offered = question(MomentOutput.emotionKey, faces + ["deadpan"])
        let first = try await answers(b, tool, [offered])
        XCTAssertEqual(first[MomentOutput.emotionKey]?.choice, "deadpan")
        let again = try await answers(b, tool, [offered])
        XCTAssertNotEqual(again[MomentOutput.emotionKey]?.choice, "deadpan", "not twice running")
        let plain = try await answers(brain(facts: second), tool, [question(MomentOutput.emotionKey, faces)])
        XCTAssertTrue(["determined", "grumpy"].contains(plain[MomentOutput.emotionKey]?.choice ?? ""), "\(String(describing: plain[MomentOutput.emotionKey]))")
    }

    /// Through the pipeline, with the rules brain: the emotion question
    /// offers a meme face at its moment alone, and the Moment shows it, as
    /// the board draws it. A failed check, then a 2nd (deadpan), a 3rd
    /// (the upset skit, a silent scream), the fix (smug) and the turn done
    /// after it, the fix's echo.
    func testAMemeFaceReachesTheMoment() async throws {
        try requireVoice()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("memes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("memes.json")
        try Data(#"""
            {"name": "memes", "case": "the meme faces", "why": "each at its moment",
             "steps": [{"event": "turn started", "at": "0s", "workspace": "memes"},
              {"event": "command", "at": "1m", "topic": "tests", "failed": true},
              {"event": "command", "at": "2m", "topic": "tests", "failed": true},
              {"event": "command", "at": "3m", "topic": "tests", "failed": true, "expect": {"said": "some"}},
              {"event": "command", "at": "4m", "topic": "tests", "failed": false}]}
            """#.utf8).write(to: file)
        let records = try await SkitTests.records(try Scenario(file: file), swears: true, steering: RuntimeTests.steering)
        let faces = records.map { $0.components(separatedBy: " | ")[1] }.map { m in
            ["deadpan", "silent scream", "smug"].first { m.contains("a \($0) moment") || m.contains("an \($0) moment") } ?? "-"
        }
        XCTAssertEqual(faces, ["-", "deadpan", "silent scream", "smug"], records.joined(separator: "\n"))
        XCTAssertFalse(records[2].components(separatedBy: " | ")[3].isEmpty, "the upset skit still speaks: \(records[2])")
    }
}
