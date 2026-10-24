import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What a buddy holds up on a sign about your prompt (`Signs`): the
/// pack's captions that fit its reading, your words first.
final class SignTests: XCTestCase {
    let lines = TaggedLine.parse("""
        <!-- a comment -->
        - [frustrated] {words} :(
        - [shouting] {WORDS}!!
        - [polite] {words} <3
        - [named] me?!
        - [fix] bug hunt
        - [deploy friday] on a FRIDAY?
        - [cleanup] bye bye code
        - [words] {words}
        - plain caption
        """)

    /// Pins `Signs.maxOffered` and `maxLength`: your words in a tagged
    /// line first, then your words as they are, then the tagged captions,
    /// then the rest; a caption too long for a sign is left out.
    func testYourWordsComeFirst() {
        let reading = PromptReading(length: .sentence, kind: .fix, tone: .frustrated, phrases: ["still broken", "a much longer phrase"])
        XCTAssertEqual(Signs.offered(lines, reading: reading, calendar: []),
                       ["still broken :(", "still broken", "bug hunt", "plain caption"], "a phrase of 20 characters is too long")
        XCTAssertEqual(Signs.maxOffered, 6)
        XCTAssertEqual(Signs.maxLength, 18)
        let shouted = PromptReading(length: .words, tone: .shouting, phrases: ["still broken"])
        XCTAssertEqual(Signs.offered(lines, reading: shouted, calendar: []).first, "STILL BROKEN!!", "{WORDS} in capitals")
    }

    /// Pins `Signs.maxYourWords`: at most three of the six are your words,
    /// so a named or frustrated prompt with two or three phrases still
    /// gets its tagged captions, as the pack's signs.md fills them.
    func testYourWordsLeaveRoomForTaggedCaptions() {
        let pack = TaggedLine.parse("""
            - [frustrated] {words} :(
            - [frustrated] {words}?!
            - [frustrated] {words}. again.
            - [named] me?!
            - [named] you rang?
            - [fix frustrated] bug, again
            - [fix] bug hunt
            - [words] {words}
            """)
        XCTAssertEqual(Signs.maxYourWords, 3)
        let two = PromptReading(length: .sentence, named: ["Boop"], kind: .fix, tone: .frustrated, phrases: ["still broken", "why"])
        XCTAssertEqual(Signs.offered(pack, reading: two, name: "Boop", calendar: []),
                       ["still broken :(", "why :(", "still broken?!", "me?!", "you rang?", "bug, again"])
        var three = two
        three.phrases = ["still broken", "why", "again"]
        XCTAssertEqual(Signs.offered(pack, reading: three, name: "Boop", calendar: []),
                       ["still broken :(", "why :(", "again :(", "me?!", "you rang?", "bug, again"])
        three.named = []
        XCTAssertEqual(Signs.offered(pack, reading: three, name: "Boop", calendar: []),
                       ["still broken :(", "why :(", "again :(", "bug, again", "bug hunt"], "three of your words at most, whatever's left")
    }

    /// A caption fits only a reading with every one of its tags: your
    /// name said, the kind, and the calendar's (a deploy on a Friday).
    func testTagsNeedTheReadingAndTheCalendar() {
        let named = PromptReading(length: .words, named: ["Pip"], kind: .feature)
        XCTAssertEqual(Signs.offered(lines, reading: named, name: "Pip", calendar: []), ["me?!", "plain caption"])
        XCTAssertEqual(Signs.offered(lines, reading: named, name: "Bo", calendar: []), ["plain caption"], "only its own name")
        let deploy = PromptReading(length: .words, kind: .deploy)
        XCTAssertEqual(Signs.offered(lines, reading: deploy, calendar: ["friday", "day"]), ["on a FRIDAY?", "plain caption"])
        XCTAssertEqual(Signs.offered(lines, reading: deploy, calendar: ["day"]), ["plain caption"])
        XCTAssertEqual(Signs.offered([], reading: deploy, calendar: []), [], "a pack with no signs.md holds up none")
    }

    /// Only a prompt's reading gets the sign question, and the sign Jev
    /// picks rides on the reaction (`do`'s `sign`) and in HISTORY's line;
    /// a caption it wasn't offered is dropped.
    func testReactAsksForASignOnlyForAPrompt() throws {
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, speaks: { false }, signs: lines)
        let log = Transcript.log().view(now: 0)
        let reading = Event(at: 0, source: .claude, type: .prompt, specificType: "reading", session: "s1",
                            data: PromptReading(length: .sentence, kind: .cleanup).facts)
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        XCTAssertNil(react.questions(now: poke, log: log).first { $0.key == Signs.questionKey })
        let sign = try XCTUnwrap(react.questions(now: reading, log: log).first { $0.key == Signs.questionKey })
        XCTAssertEqual(sign.options.map { $0.name }, ["none", "bye bye code", "plain caption"])
        func answer(_ choices: [String: String]) -> OutputResult? {
            react.run(choices.mapValues { Answer(choice: $0, probabilities: [$0: 1]) }, now: reading, log: log)
        }
        let did = try XCTUnwrap(answer(["react.mood": "happy", Signs.questionKey: "bye bye code"])).message
        XCTAssertTrue(did.contains(#"holding up a sign: "bye bye code""#), did)
        XCTAssertEqual(queued.last?.sign, "bye bye code")
        XCTAssertEqual(queued.last?.args.json, #"{"sign":"bye bye code","say":{},"mood":"happy","loops":1}"#)
        _ = answer(["react.mood": "happy", Signs.questionKey: "something else"])
        XCTAssertNil(queued.last?.sign, "only an offered caption")
    }

    /// With several buddies, the reading records whose names you said, its
    /// line names them, and each buddy's sign question offers its `named`
    /// captions only when you said its own name.
    func testEachBuddyHearsWhetherYouSaidItsOwnName() throws {
        let pack = CharacterPack.active
        let buddies = [Buddy(id: "left", pack: pack.named("Pip")), Buddy(id: "right", pack: pack.named("Bo"))]
        let pipeline = Pipeline(buddies.map { ($0, Core(config: .init(pack: $0.pack))) }, view: TranscriptView(rules: .init(), seed: 1))
        let step = pipeline.agent(Event(at: 1, source: .claude, type: .turn, phase: .start, specificType: "UserPromptSubmit", session: "s1",
                                        data: ["prompt": "nice one bo, now the docs"]))
        let reading = try XCTUnwrap(step.recorded.first { $0.type == .prompt })
        XCTAssertEqual(reading.buddy, "left", "the session's buddy")
        XCTAssertEqual(reading["named"], .array(["Bo"]))
        XCTAssertTrue(step.views.contains { $0.line.contains("and said Bo's name.") }, "\(step.views.map(\.line))")
        let log = pipeline.transcript.view(now: 1)
        func signs(_ buddy: Buddy) -> [String] {
            ReactOutput(queue: { _, _ in }, blocked: { nil }, pack: buddy.pack, signs: lines).offered(reading, log)
        }
        XCTAssertEqual(signs(buddies[1]), ["me?!", "plain caption"])
        XCTAssertEqual(signs(buddies[0]), ["plain caption"], "its own name wasn't said")
    }

    /// Every caption in each pack's signs.md fits a sign once filled in
    /// with a short phrase, in the board's fonts (printable ASCII), and
    /// its tags are ones a reading or the calendar can have: the calendar
    /// signs hear is `Core.calendar`, never the board's or the tiers' tags.
    func testThePacksSignsFit() throws {
        let known = Set(PromptReading.Kind.allCases.map(\.rawValue) + PromptReading.Tone.allCases.map(\.rawValue)
            + PromptReading.Length.allCases.map(\.rawValue) + ["named", "words"] + Occasions.calendarTags)
        for pack in ["boop", "pixel"] {
            let file = CharacterPackTests.repo.appendingPathComponent("characters/\(pack)/steering/signs.md")
            let signs = TaggedLine.parse(try String(contentsOf: file, encoding: .utf8))
            XCTAssertGreaterThan(signs.count, 10, pack)
            for line in signs {
                let filled = line.text.replacingOccurrences(of: "{words}", with: "ok").replacingOccurrences(of: "{WORDS}", with: "OK")
                XCTAssertLessThanOrEqual(filled.count, Signs.maxLength, "\(pack): \(line.text)")
                XCTAssertTrue(filled.unicodeScalars.allSatisfy { (32...126).contains($0.value) }, "\(pack): \(line.text)")
                XCTAssertTrue(Set(line.tags).isSubset(of: known), "\(pack): \(line.tags)")
            }
        }
    }

    /// A demo's prompt carries its reading, which plays the same on any
    /// Mac, and its brain may hold up any sign that fits a sign.
    func testADemoCarriesAReadingAndASign() throws {
        let prompt = try DemoScript(#"{"agent": "prompt", "text": "still broken", "reading": {"kind": "fix", "phrases": ["still broken"]}}"#)
        guard case .agent(let a) = prompt.steps[0].what else {
            XCTFail("not an agent step")
            return
        }
        XCTAssertEqual(a.reading, .init(kind: .fix, phrases: ["still broken"]))
        try XCTAssertThrowsError(try DemoScript(#"{"agent": "reply", "text": "ok", "reading": {"kind": "fix"}}"#))
        try XCTAssertEqual(try DemoScript(#"{"brain": {"react.mood": "happy", "react.sign": "still broken :("}}"#).problems(), [])
        try XCTAssertEqual(try DemoScript(#"{"brain": {"react.sign": "a sign that is far too long"}}"#).problems().count, 1)
    }
}
