import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Your prompt, read on the Mac (`PromptIntake`): scrubbed of secrets,
/// counted, labelled, and only its reading logged and heard by the brain.
final class PromptTests: XCTestCase {
    /// Every secret shape becomes `[secret]`, keeping the name it was given;
    /// ordinary words, paths and numbers stay.
    func testTheScrubberTakesSecretsOut() {
        let cases: [(String, String)] = [
            ("use sk-proj-8f2aQz91kLmN0pQrStUv to call it", "use [secret] to call it"),
            ("token ghp_abcdefghijklmnopqrstuvwxyz0123456789", "token [secret]"),
            ("aws AKIAIOSFODNN7EXAMPLE here", "aws [secret] here"),
            ("slack xoxb-1234567890-abcdefghij", "slack [secret]"),
            ("set API_KEY=abc123def456 and go", "set API_KEY=[secret] and go"),
            ("password: hunter2!", "password: [secret]"),
            (#"{"token": "abc.def"}"#, #"{"token": [secret]}"#),
            ("open https://me:pa55word@example.com/x", "open https://[secret]@example.com/x"),
            ("GET /cb?code=1&access_token=zzz&x=2", "GET /cb?code=1&access_token=[secret]&x=2"),
            ("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl ok", "jwt [secret] ok"),
            ("mail jo.smith+boop@example.co.uk now", "mail [secret] now"),
            ("hash 3f786850e387550fdab836ed7e6dc881de23001b done", "hash [secret] done"),
            ("-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----", "[secret]"),
        ]
        for (text, scrubbed) in cases { XCTAssertEqual(Scrubber.scrub(text), scrubbed, text) }
        let plain = "fix src/components/UploadButton.tsx: the 413 at 5MB, then run npm test (v1.4.0)"
        XCTAssertEqual(Scrubber.scrub(plain), plain, "paths, numbers and versions stay")
    }

    /// Pins `PromptReading.Length.bounds`: a few words under 25 characters,
    /// a sentence under 150, a paragraph under 600, an essay beyond.
    func testTheLengthBands() {
        for (n, length) in [(24, PromptReading.Length.words), (25, .sentence), (149, .sentence), (150, .paragraph),
                            (599, .paragraph), (600, .essay)] {
            XCTAssertEqual(PromptReading.Length(String(repeating: "a", count: n)), length, "\(n)")
        }
        XCTAssertEqual(PromptReading.Length("   continue \n"), .words, "the spaces around it don't count")
    }

    /// Counted with no model: the buddy's name as a word, in any case, and
    /// the tone the words plainly show; capitals are shouting.
    func testCountingSeesTheNameAndThePlainTone() {
        func read(_ text: String) -> PromptReading { PromptReading(counting: text, names: ["Pip"]) }
        XCTAssertTrue(read("ok pip, watch this").named)
        XCTAssertFalse(read("pipe the logs to a file").named, "a word, not part of one")
        XCTAssertEqual(read("WHY IS THE LOGIN STILL BROKEN").tone, .shouting)
        XCTAssertNil(read("fix the API").tone, "a capitalised word isn't shouting")
        XCTAssertEqual(read("please add a retry").tone, .polite)
        XCTAssertEqual(read("ultrathink: why is it stale").tone, .careful)
        XCTAssertEqual(read("just quickly fix it").tone, .rushed)
        XCTAssertEqual(read("lol ok try again 🙃").tone, .playful)
        XCTAssertNil(read("fix the login redirect").tone)
        XCTAssertNil(read("fix the login redirect").kind, "the kind needs a labeler")
    }

    /// A labeler's phrases are kept only if they really are in the prompt,
    /// fit a sign and hold no secret, at most three; its shouting is
    /// dropped, and a counted tone stands over its calm.
    func testALabelIsCheckedAgainstThePrompt() {
        let text = Scrubber.scrub("it's Still Broken again, key sk-proj-8f2aQz91kLmN0pQrStUv, please fix")
        var reading = PromptReading(counting: text, names: [])
        reading.label(.init(kind: .fix, tone: .calm, phrases: ["still broken", "ensure stability", "[secret]", "it's Still Broken again, key",
                                                              "again", "please", "fix"]), in: text)
        XCTAssertEqual(reading.kind, .fix)
        XCTAssertEqual(reading.phrases, ["Still Broken", "again", "please"], "its own spelling, three at most")
        XCTAssertEqual(reading.tone, .polite, "the counted tone over the labeler's calm")
        reading.label(.init(tone: .frustrated), in: text)
        XCTAssertEqual(reading.tone, .frustrated, "more than calm wins over a counted cue")
        var plain = PromptReading(counting: "ship it to prod", names: [])
        plain.label(.init(kind: .deploy, tone: .shouting), in: "ship it to prod")
        XCTAssertNil(plain.tone, "shouting is counted, never heard")
    }

    /// The reading round-trips through an event's facts, and the labeler's
    /// three lines parse, anything off a list dropped.
    func testTheReadingAsFactsAndTheLabelersReply() {
        let reading = PromptReading(length: .sentence, named: true, kind: .cleanup, tone: .playful, phrases: ["bye bye"])
        XCTAssertEqual(PromptReading(facts: reading.facts), reading)
        XCTAssertNil(PromptReading(facts: ["kind": "fix"]), "not a reading without its length")
        XCTAssertEqual(AppleIntelligenceLabeler.parse("kind: fix\ntone:  Frustrated \nphrases: still broken | keep happening"),
                       .init(kind: .fix, tone: .frustrated, phrases: ["still broken", "keep happening"]))
        XCTAssertEqual(AppleIntelligenceLabeler.parse("Kind: refactoring\ntone: grumpy\nphrases: none"), .init())
    }

    /// The prompt leaves the turn start, which says its reading follows
    /// and so doesn't wake the brain; the reading does, and Jev reads it,
    /// never the words but "Your words". A turn start with no prompt still
    /// wakes it.
    func testOnlyTheReadingReachesTheBrain() {
        let rig = CoreRig()
        let fx = rig.send(.turnStart, prompt: "it's still broken, please fix it")
        XCTAssertFalse(rig.pipeline.transcript.events.contains { $0["prompt"] != nil }, "no prompt in the transcript")
        XCTAssertEqual(woke(fx), [#"You asked claude on "landing" in a sentence, politely."#])
        let start = rig.pipeline.transcript.events.first { $0.kind == "turn_start" }
        XCTAssertEqual(start?[PromptIntake.readingFollows], .bool(true))
        rig.send(.turnEnd)
        rig.wait(5000)
        XCTAssertEqual(woke(rig.send(.turnStart)), [#"claude started turn 2 on "landing"."#], "no prompt: the turn start wakes it")
        XCTAssertEqual(EventLine.asked(PromptReading(length: .essay, named: true, kind: .fix, tone: .frustrated), agent: "codex",
                                       thread: #""api""#, name: "Pip"),
                       #"You asked codex on "api" for a fix, at length, frustrated, and said Pip's name."#)
        XCTAssertEqual(EventLine.yourWords(["still broken", "please"]), #"Your words: "still broken", "please"."#)
        XCTAssertNil(EventLine.yourWords([]))
    }

    /// The intake hands on the reading at once with no labeler, and on
    /// `home` once one answers, the prompt scrubbed before it reads it.
    func testTheIntakeReadsOnceAndHandsOn() {
        final class Seen: PromptLabeler, @unchecked Sendable {
            var text: String?
            func label(_ text: String) async -> PromptReading.Labels? {
                self.text = text
                return .init(kind: .fix, tone: .frustrated, phrases: ["still broken"])
            }
        }
        let home = DispatchQueue(label: "test.home")
        let turn = Event(at: 0, source: .claude, type: .turn, phase: .start, specificType: "UserPromptSubmit", session: "s1")
        let got = Lines()
        PromptIntake(labeler: nil, home: home, names: { ["Pip"] }, deliver: { r, _ in got.add("\(r.length) \(r.named)") })
            .read("hey pip", about: turn)
        XCTAssertEqual(got.all, ["words true"], "at once, with no labeler")
        let seen = Seen()
        PromptIntake(labeler: seen, home: home, names: { [] }, deliver: { r, _ in got.add("\(r.kind!) \(r.phrases)") })
            .read("still broken, key sk-proj-8f2aQz91kLmN0pQrStUv", about: turn)
        eventually("the labeler's reading") { got.all.count == 2 }
        XCTAssertEqual(got.all.last, #"fix ["still broken"]"#)
        XCTAssertEqual(seen.text, "still broken, key [secret]", "it reads the scrubbed prompt")
    }
}
