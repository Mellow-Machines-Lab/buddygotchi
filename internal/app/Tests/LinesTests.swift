import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Boop's line (`Lines`): one short sentence about what just happened,
/// held low, and said aloud with Settings' Voice (`AppSettings.Voice`,
/// `Speaker`).
final class LinesTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    var rows: [TaggedLine] { RuntimeTests.steering.signs }

    static let finish = RemarksTests.finish()
    static var check: Event {
        var e = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        e.seq = 100
        return e
    }
    static let thread: JSONValue = ["name": "buddygotchi", "agent": "claude"]

    func win(minutes: Int64 = 20, checksFailed: Int64 = 0) -> Facts {
        var f = RemarksTests().win(minutes: minutes)
        f["checks_failed"] = .int(checksFailed)
        f["thread"] = Self.thread
        return f
    }
    func failed(minutes: Int64 = 20) -> Facts {
        ["outcome": "failed", "length_ms": .int(minutes * 60_000), "length": .string(Band.length(ms: minutes * 60_000)),
         "tools": 3, "thread": Self.thread]
    }
    func check(_ result: String, before: Int64, topic: String = "tests") -> Facts {
        ["topic": .string(topic), "result": .string(result), "failed_before": .int(before), "thread": Self.thread]
    }

    func pool(_ moment: String, _ slot: RulesBrain.Slot, _ facts: Facts, mood: String = "calm", swears: Bool = false) -> [String] {
        BoopKit.Lines.pool(rows, moment: moment, slot: slot, facts: facts, mood: mood, swears: swears, quiet: false).map(\.text)
    }

    /// Pins `BoopKit.Lines.moment`: the skits' but `back`, and a failed check
    /// before its skit.
    func testWhichMomentsHaveALine() {
        func skit(_ id: String, swears: Bool = false) -> Skits.Play { Skits.Play(skit: Skit(id: id, slots: []), swears: swears) }
        XCTAssertEqual(BoopKit.Lines.moment(skit: skit("win"), slot: .doneLong), "win")
        XCTAssertEqual(BoopKit.Lines.moment(skit: skit("upset"), slot: .failed), "upset")
        XCTAssertEqual(BoopKit.Lines.moment(skit: skit("upset"), slot: .checkFailing), "upset")
        XCTAssertEqual(BoopKit.Lines.moment(skit: skit("fix"), slot: .checkFixed), "fix")
        XCTAssertNil(BoopKit.Lines.moment(skit: skit("back"), slot: .back))
        XCTAssertEqual(BoopKit.Lines.moment(skit: nil, slot: .checkFailed), "oops")
        XCTAssertEqual(BoopKit.Lines.moment(skit: nil, slot: .checkFailing), "oops", "the 2nd in a row, before the skit")
        XCTAssertNil(BoopKit.Lines.moment(skit: nil, slot: .doneShort), "a short win: none")
        XCTAssertNil(BoopKit.Lines.moment(skit: nil, slot: .other))
    }

    /// Each moment's lines, filled from the facts, by what's true.
    func testEachMomentsLinesSayWhatHappened() throws {
        try requirePack("boop")
        let wins = pool("win", .doneLong, win())
        XCTAssertGreaterThanOrEqual(wins.count, 6)
        XCTAssertTrue(wins.allSatisfy { $0.lowercased().contains("buddygotchi") }, "\(wins)")
        XCTAssertTrue(wins.contains("Yay, buddygotchi, done!"))
        // A very long win, a hard-won one: their own rows.
        let long = pool("win", .doneVeryLong, win(minutes: 90))
        XCTAssertTrue(long.contains("Phew, buddygotchi took ages. Done!"), "\(long)")
        XCTAssertFalse(long.contains("Yay, buddygotchi, done!"))
        XCTAssertTrue(pool("win", .doneLong, win(checksFailed: 2)).contains("2 fails, but buddygotchi is done."))
        // A cross or sad mood doesn't cheer.
        for mood in ["cross", "sad"] {
            let glum = pool("win", .doneLong, win(checksFailed: 2), mood: mood)
            XCTAssertFalse(glum.isEmpty)
            XCTAssertTrue(glum.allSatisfy { !$0.contains("!") && !$0.contains("Yay") }, "\(mood): \(glum)")
        }
        // A failed turn, and the 3rd failed check in a row: "again".
        XCTAssertTrue(pool("upset", .failed, failed()).contains("Aw. Buddygotchi broke."))
        let again = pool("upset", .checkFailing, check("failed", before: 2))
        XCTAssertTrue(again.contains("Oh man, the tests failed again."), "\(again)")
        XCTAssertTrue(again.contains("The tests, 3 in a row. Ugh."), "\(again)")
        XCTAssertTrue(pool("upset", .gaveUp, failed()).contains("Buddygotchi is stuck. Ugh."))
        // A fix, and the 1st and 2nd failed check.
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 1)).contains("Phew. The tests, fixed."))
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 3)).contains("3 tries. The tests, fixed!"))
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 3)).contains("Took 3 goes. The tests, fixed!"))
        let first = pool("oops", .checkFailed, check("failed", before: 0, topic: "build"))
        XCTAssertTrue(first.contains("Uh oh, the build failed."), "\(first)")
        XCTAssertFalse(first.contains("The build failed again."))
        XCTAssertTrue(pool("oops", .checkFailing, check("failed", before: 1)).contains("The tests failed again."))
    }

    /// A swear row only when the skit swears (Settings' swearing on, and
    /// the failures piled up: `Skits.play`).
    func testASwearOnlyWhenTheSkitSwears() throws {
        try requirePack("boop")
        let swear = Set(rows.filter { $0.tags.contains("swear") }.map(\.text))
        XCTAssertFalse(swear.isEmpty)
        for (slot, facts) in [(RulesBrain.Slot.failed, failed()), (.checkFailing, check("failed", before: 2))] {
            let mild = BoopKit.Lines.pool(rows, moment: "upset", slot: slot, facts: facts, mood: "calm", swears: false, quiet: false).map(\.row)
            XCTAssertTrue(Set(mild).isDisjoint(with: swear), "\(slot): \(mild)")
            let sworn = BoopKit.Lines.pool(rows, moment: "upset", slot: slot, facts: facts, mood: "calm", swears: true, quiet: false).map(\.row)
            XCTAssertFalse(Set(sworn).isDisjoint(with: swear), "\(slot)")
        }
    }

    /// On Quiet, no line.
    func testQuietHasNoLine() throws {
        try requirePack("boop")
        var rng = SplitMix64(seed: 1)
        XCTAssertNil(BoopKit.Lines.pick(rows, moment: "upset", slot: .failed, facts: failed(), mood: "calm", swears: false, quiet: true, rng: &rng))
        XCTAssertNotNil(BoopKit.Lines.pick(rows, moment: "upset", slot: .failed, facts: failed(), mood: "calm", swears: false, quiet: false, rng: &rng))
    }

    /// Never the same row twice running, while another fits.
    func testNeverTheSameRowTwiceRunning() throws {
        try requirePack("boop")
        var rng = SplitMix64(seed: 7)
        var last: String?
        for _ in 0..<40 {
            let (row, _) = try XCTUnwrap(BoopKit.Lines.pick(rows, moment: "oops", slot: .checkFailed, facts: check("failed", before: 0), mood: "calm",
                                                    swears: false, quiet: false, avoiding: last, rng: &rng))
            XCTAssertNotEqual(row, last)
            last = row
        }
    }

    /// Pins `BoopKit.Lines.maxLength` and the low sign's rows: every row of the
    /// pack, filled with the longest `{what}` and a two-digit `{n}`, fits
    /// two rows of 26; and a row that wouldn't is left out.
    func testEveryLineFitsTheLowSign() throws {
        try requirePack("boop")
        XCTAssertEqual(BoopKit.Lines.maxLength, 40)
        XCTAssertEqual(BoopKit.Lines.rowLength, 26)
        let lines = rows.filter { $0.tags.first == "line" }
        XCTAssertGreaterThan(lines.count, 40)
        let moments: Set<String> = ["win", "upset", "fix", "oops"]
        let tags: Set<String> = ["long", "hard", "glum", "check", "stuck", "swear", "again"]
        for line in lines {
            XCTAssertTrue(moments.contains(line.tags[1]), line.text)
            XCTAssertTrue(Set(line.tags.dropFirst(2)).isSubset(of: tags), line.text)
            XCTAssertFalse(line.text.contains("?"), "no questions: \(line.text)")
            for what in ["the deploy", String(repeating: "w", count: BoopKit.Lines.whatLength)] {
                let filled = BoopKit.Lines.filled(line.text, what: what, n: 10)
                XCTAssertNotNil(filled, "\(line.text) with \(what)")
            }
        }
        XCTAssertTrue(BoopKit.Lines.fits("Phew, buddygotchi took ages. Done!"))
        XCTAssertFalse(BoopKit.Lines.fits(String(repeating: "a", count: 27)))
        // A long thread's name is cut to fit.
        var f = win()
        f["thread"] = ["name": "a-very-long-workspace-name-indeed"]
        XCTAssertFalse(pool("win", .doneLong, f).isEmpty)
    }

    // MARK: In the Moment

    /// A rig whose Voice is `voice`, on a call or not.
    @MainActor func rig(_ voice: AppSettings.Voice, onCall: Bool = false, talk: Talk = .normal) -> InviteRig {
        let rig = InviteRig()
        rig.talk = talk
        rig.react.voice = { voice }
        rig.react.hushed = { onCall }
        return rig
    }

    /// With the board's sounds, a long win's line is a low Moment behind
    /// the finish, its record's `line`; the finish keeps its take, and the
    /// line's words never go to HISTORY.
    @MainActor func testSoundsShowTheLineAndKeepTheTake() throws {
        try requirePack("boop")
        let rig = rig(.sounds)
        let result = try XCTUnwrap(rig.run(Self.finish, win()))
        XCTAssertEqual(rig.sent.count, 2)
        let line = try XCTUnwrap(rig.sent.last?.sign)
        XCTAssertTrue(line.contains("buddygotchi"), line)
        XCTAssertEqual(rig.sent.last?.low, true)
        XCTAssertNil(rig.sent.last?.aloud)
        XCTAssertFalse(rig.sent.first?.say?.takes.isEmpty ?? true, "the board plays its take")
        let after = try XCTUnwrap(rig.react.following)
        XCTAssertEqual(after.facts["line"]?.string, line)
        XCTAssertNil(after.facts["voice"])
        XCTAssertFalse(after.message.contains(line), after.message)
        XCTAssertFalse(result.message.contains(line))
    }

    /// Speaking, on this Mac or in the cloud: the same line, said aloud by
    /// the Mac, and no take on the board.
    @MainActor func testSpeakingSaysTheLineAndPlaysNoTake() throws {
        try requirePack("boop")
        for voice in [AppSettings.Voice.speaks, .cloud] {
            let rig = rig(voice)
            let result = try XCTUnwrap(rig.run(Self.finish, win()))
            let line = try XCTUnwrap(rig.sent.last?.sign)
            XCTAssertEqual(rig.sent.last?.aloud, line, "\(voice)")
            XCTAssertNil(rig.sent.first?.aloud)
            XCTAssertEqual(rig.sent.first?.say?.takes, [], "\(voice)")
            XCTAssertEqual(result.facts["takes"], .array([]))
            XCTAssertEqual(rig.react.following?.facts["voice"]?.string, voice.rawValue)
        }
    }

    /// The agent's offered line is the line: said aloud too.
    @MainActor func testTheAgentsLineIsSaidAloud() throws {
        try requirePack("boop")
        let rig = rig(.speaks)
        var card = Card(kind: .result, text: "shipped the nav")
        card.lines = [Card.Line(says: "nav, shipped. nice", feeling: "happy")]
        rig.card = card
        rig.run(Self.finish, win())
        XCTAssertEqual(rig.sent.last?.aloud, "nav, shipped. nice")
        XCTAssertEqual(rig.react.following?.facts["line"]?.string, "nav, shipped. nice")
        XCTAssertEqual(rig.react.following?.facts["offered_line"], true)
    }

    /// A failed check's line is the Moment's own low sign, over a fix's;
    /// HISTORY says only that it held one up.
    @MainActor func testACheckHoldsItsLineLow() throws {
        try requirePack("boop")
        let rig = rig(.speaks)
        let result = try XCTUnwrap(rig.run(Self.check, check("failed", before: 0), face: "annoyed"))
        XCTAssertEqual(rig.sent.count, 1)
        let line = try XCTUnwrap(rig.sent.first?.sign)
        XCTAssertTrue(line.lowercased().contains("the tests"), line)
        XCTAssertEqual(rig.sent.first?.low, true)
        XCTAssertEqual(rig.sent.first?.aloud, line)
        XCTAssertEqual(result.facts["line"]?.string, line)
        XCTAssertEqual(result.facts["voice"], "speaks")
        XCTAssertFalse(result.message.contains(line), result.message)
        // The fix: its line, said.
        let fixed = try XCTUnwrap(rig.run(Self.check, check("ok", before: 2), face: "proud"))
        XCTAssertNotNil(fixed.facts["line"])
        XCTAssertEqual(rig.sent.last?.aloud, rig.sent.last?.sign)
    }

    /// On a call the Mac says nothing: the line shows, and the board's
    /// take plays as ever (which `speaks` keeps quiet itself).
    @MainActor func testOnACallNothingIsSaid() throws {
        try requirePack("boop")
        let rig = rig(.speaks, onCall: true)
        let result = try XCTUnwrap(rig.run(Self.finish, failed()))
        XCTAssertNotNil(rig.sent.last?.sign)
        XCTAssertTrue(rig.sent.allSatisfy { $0.aloud == nil })
        XCTAssertNil(rig.react.following?.facts["voice"])
        XCTAssertNotEqual(result.facts["takes"], .array([]))
    }

    /// On Quiet, no line and nothing said.
    @MainActor func testQuietSaysNoLine() throws {
        try requirePack("boop")
        let rig = rig(.speaks, talk: .quiet)
        rig.run(Self.check, check("failed", before: 0), face: "annoyed")
        XCTAssertNil(rig.sent.first?.sign)
        XCTAssertNil(rig.sent.first?.aloud)
    }

    // MARK: The setting

    /// Old settings files load as `sounds`; a choice round-trips; one this
    /// version doesn't know is `sounds`.
    func testTheVoiceSettingsCoding() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"talk":"normal","volume":6}"#.utf8))
        XCTAssertEqual(old.voice, .sounds)
        XCTAssertNil(old.cloudVoice)
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(written.contains("voice"), "the default isn't written")
        var s = AppSettings()
        s.voice = .cloud
        s.cloudVoice = CloudSpeaker.Config(url: "http://localhost:9/v1", model: "m", voice: "v")
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.voice, .cloud)
        XCTAssertEqual(back.cloudVoice, s.cloudVoice)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"voice":"opera","cloudVoice":{"voice":"nova"}}"#.utf8))
        XCTAssertEqual(unknown.voice, .sounds)
        XCTAssertEqual(unknown.cloudVoice, CloudSpeaker.Config(voice: "nova"), "a missing key keeps its default")
        XCTAssertNil(AppSettings.Voice.sounds.speaker(cloud: nil, key: { nil }))
        XCTAssertTrue(AppSettings.Voice.speaks.speaker(cloud: nil, key: { nil }) is SystemSpeaker)
        XCTAssertTrue(AppSettings.Voice.cloud.speaker(cloud: nil, key: { nil }) is CloudSpeaker)
        for voice in AppSettings.Voice.allCases { XCTAssertFalse(voice.about("Boop").isEmpty) }
    }

    /// The key: `BOOP_VOICE_KEY` first.
    func testTheKeyComesFromTheEnvironmentFirst() {
        XCTAssertEqual(CloudSpeaker.key(stateDir: URL(fileURLWithPath: "/tmp/x"), environment: ["BOOP_VOICE_KEY": " sk-test \n"]), "sk-test")
    }

    // MARK: The cloud voice, against a stub

    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var seen: [URLRequest] = []
        nonisolated(unsafe) static var bodies: [[String: Any]] = []
        nonisolated(unsafe) static var answer: (status: Int, data: Data, delay: TimeInterval) = (200, Data("ID3audio".utf8), 0)
        static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open()
                var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: 4096); if n <= 0 { break }; bytes.append(buffer, count: n) }
                stream.close()
                data = bytes
            }
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let answer = Self.lock.withLock {
                Self.seen.append(request)
                Self.bodies.append(body)
                return Self.answer
            }
            let request = self.request, client = self.client
            DispatchQueue.global().asyncAfter(deadline: .now() + answer.delay) { [self] in
                let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: [:])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: answer.data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }

    /// What a speaker heard, instead of a sound.
    final class Heard: Speaker, @unchecked Sendable {
        var lines: [String] = []
        let lock = NSLock()
        func speak(_ line: String, mood: String) async { lock.withLock { lines.append("\(line) (\(mood))") } }
    }

    final class Played: @unchecked Sendable {
        var audio: [Data] = []
        let lock = NSLock()
    }

    func cloud(_ heard: Heard, _ played: Played, key: String? = "sk-test", deadline: TimeInterval = 1.5) -> CloudSpeaker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return CloudSpeaker(config: CloudSpeaker.Config(url: "https://voice.example/v1/"), key: { key }, session: URLSession(configuration: config),
                            fallback: heard, deadline: deadline, play: { data in played.lock.withLock { played.audio.append(data) } })
    }

    override func setUpWithError() throws {
        Stub.seen = []
        Stub.bodies = []
        Stub.answer = (200, Data("ID3audio".utf8), 0)
    }

    /// The request: a POST of the line, the model, the voice and how to say
    /// it, with the key as a bearer token; its audio played, nothing else.
    func testTheCloudRequestAndItsAudio() async throws {
        let heard = Heard(), played = Played()
        await cloud(heard, played).speak("Yay, buddygotchi, done!", mood: "proud")
        let request = try XCTUnwrap(Stub.seen.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://voice.example/v1/audio/speech")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(Stub.bodies.first)
        XCTAssertEqual(Set(body.keys), ["model", "voice", "input", "response_format", "instructions"], "nothing else is sent")
        XCTAssertEqual(body["input"] as? String, "Yay, buddygotchi, done!")
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(body["voice"] as? String, "coral")
        XCTAssertTrue((body["instructions"] as? String)?.contains("proud") ?? false)
        XCTAssertEqual(played.audio, [Data("ID3audio".utf8)])
        XCTAssertEqual(heard.lines, [])
    }

    /// An error, no key, or no answer in time: this Mac's voice says it.
    func testTheCloudFallsBackToThisMac() async throws {
        let heard = Heard(), played = Played()
        Stub.answer = (500, Data("{}".utf8), 0)
        await cloud(heard, played).speak("Aw. Buddygotchi broke.", mood: "sad")
        XCTAssertEqual(heard.lines, ["Aw. Buddygotchi broke. (sad)"])
        // No key: nothing sent.
        Stub.seen = []
        await cloud(heard, played, key: nil).speak("Oops. The tests failed.", mood: "annoyed")
        XCTAssertTrue(Stub.seen.isEmpty)
        XCTAssertEqual(heard.lines.count, 2)
        // Too slow: it doesn't wait past the deadline.
        Stub.answer = (200, Data("ID3audio".utf8), 2)
        let start = Date()
        await cloud(heard, played, deadline: 0.3).speak("Phew. The tests, fixed.", mood: "proud")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
        XCTAssertEqual(heard.lines.last, "Phew. The tests, fixed. (proud)")
        XCTAssertTrue(played.audio.isEmpty)
    }
}
