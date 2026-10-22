import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Boop's ears as `Hearing` and `SoundDetector` decide them, with no mic:
/// which word or sound was heard, the name's gate, the debounce, the
/// mishearing and its odds, and the line each makes.
final class HearingTests: XCTestCase {

    /// Most words count only within 3 s of the name, so talk at the desk
    /// doesn't set Boop off; praise and "who needs me" count on their own.
    /// The name gates the word after it, and is heard alone only with none.
    func testTheNameGatesTheWords() {
        XCTAssertEqual(Hearing.nameGateMs, 3000)
        XCTAssertEqual(Hearing.ungated, ["good", "who"])
        var h = Hearing(name: "Pip")
        XCTAssertNil(h.words("let's sit down, no rush, then stop", at: 0), "no name")
        h.newUtterance()
        XCTAssertEqual(h.words("good boy", at: 10_000)?.what, "good")
        h.newUtterance()
        XCTAssertEqual(h.words("who needs me", at: 20_000)?.what, "who")
        h.newUtterance()
        XCTAssertEqual(h.words("Pip", at: 30_000), Hearing.Heard(what: "name"))
        XCTAssertEqual(h.words("Pip no", at: 31_000)?.what, "no", "a word right after the name, despite the debounce")
        h.newUtterance()
        XCTAssertEqual(h.words("Pip, stop!", at: 40_000)?.what, "stop", "the name and its word at once: the word")
        h.newUtterance()
        XCTAssertNil(h.words("stop", at: 44_000), "4 s after the name")
    }

    /// The recogniser writes an utterance a little at a time: a phrase is
    /// heard once it's whole, and once only; the longest phrase wins; and a
    /// new utterance starts matching again.
    func testPartialResultsAndTheLongestPhrase() {
        var h = Hearing(name: "Pip")
        XCTAssertNil(h.words("good", at: 0), "not a phrase yet")
        XCTAssertEqual(h.words("good boy", at: 100)?.what, "good")
        XCTAssertNil(h.words("good boy you", at: 5000), "already heard")
        h.newUtterance()
        XCTAssertEqual(h.words("Pip good night", at: 10_000)?.what, "bye", "good night is goodbye, not praise")
        h.newUtterance()
        XCTAssertEqual(h.words("Pip go to sleep", at: 20_000)?.what, "sleep")
        XCTAssertEqual(Hearing.phrases(name: "Pip").first, "Pip")
        XCTAssertTrue(Hearing.phrases(name: "Pip").contains("who needs me"))
    }

    /// One thing heard in 3 s at most.
    func testTheDebounce() {
        XCTAssertEqual(Hearing.debounceMs, 3000)
        var h = Hearing(name: "Pip")
        XCTAssertEqual(h.sound("bang", at: 0)?.what, "bang")
        XCTAssertNil(h.words("good boy", at: 2999))
        h.newUtterance()
        XCTAssertEqual(h.words("good boy", at: 3000)?.what, "good")
        XCTAssertNil(h.sound("whistle", at: 9000), "only the three sounds")
    }

    /// The commands Boop mishears on purpose, one time in 5, with a seeded
    /// die; never its name, praise, or a no, shh or stop.
    func testMishearingOddsAndTheWordsItNeverMishears() {
        XCTAssertEqual(Hearing.mishearOdds, 5)
        var h = Hearing(name: "Pip")
        var misheard = 0
        for i in 0..<1000 {
            h.newUtterance()
            if h.words("Pip dance", at: Int64(i) * 10_000)?.misheard == true { misheard += 1 }
        }
        XCTAssertGreaterThan(misheard, 150)
        XCTAssertLessThan(misheard, 250)
        for phrase in ["Pip", "good boy", "Pip no", "Pip shh", "Pip stop"] {
            var h = Hearing(name: "Pip")
            for i in 0..<200 {
                h.newUtterance()
                XCTAssertEqual(h.words(phrase, at: Int64(i) * 10_000)?.misheard, false, phrase)
            }
        }
        XCTAssertTrue(Hearing.canMishear.isDisjoint(with: ["good", "no", "shh", "stop", "name"]))
    }

    /// A bang is loud and over in under 300 ms; a shout is loud for 500 ms
    /// (once per loud spell); singing is a voice whose pitch swings 9
    /// semitones within 2 s. Speech's narrower swing is neither.
    func testTheSounds() {
        var d = SoundDetector()
        XCTAssertNil(d.feed(levelDb: -60, pitchHz: nil, at: 0))
        XCTAssertNil(d.feed(levelDb: -10, pitchHz: nil, at: 100))
        XCTAssertNil(d.feed(levelDb: -12, pitchHz: nil, at: 200))
        XCTAssertEqual(d.feed(levelDb: -60, pitchHz: nil, at: 300), "bang")

        var heard: [String] = []
        for t in stride(from: Int64(1000), to: 2000, by: 50) {
            if let s = d.feed(levelDb: -20, pitchHz: nil, at: t) { heard.append(s) }
        }
        XCTAssertNil(d.feed(levelDb: -60, pitchHz: nil, at: 2000), "a shout isn't a bang too")
        XCTAssertEqual(heard, ["shout"])

        var speech: [String] = []
        for i in 0..<40 {
            let hz = Float(200) * pow(2, Float(i % 5) / 12)  // within 4 semitones
            if let s = d.feed(levelDb: -35, pitchHz: hz, at: 3000 + Int64(i) * 50) { speech.append(s) }
        }
        XCTAssertEqual(speech, [], "speech's swing is no song")
        var song: [String] = []
        for i in 0..<20 {
            let hz = Float(200) * pow(2, Float(i) / 12)  // a rising run over a 19-semitone range
            if let s = d.feed(levelDb: -35, pitchHz: hz, at: 6000 + Int64(i) * 80) { song.append(s) }
        }
        XCTAssertEqual(song, ["singsong"])
    }

    /// What each thing heard reads as, a word quoted as its first phrase.
    func testTheLines() {
        XCTAssertEqual(EventLine.heard("name", name: "Pip"), "Pip heard its name.")
        XCTAssertEqual(EventLine.heard("good", name: "Pip"), #"Pip heard you say "good boy"."#)
        XCTAssertEqual(EventLine.heard("dance", misheard: true, name: "Pip"), #"Pip misheard you: "dance", or something like it."#)
        XCTAssertEqual(EventLine.heard("bang", name: "Pip"), "Pip heard a bang.")
        XCTAssertEqual(EventLine.heard("shout", name: "Pip"), "Pip heard you shout.")
        XCTAssertEqual(EventLine.heard("singsong", name: "Pip"), "Pip heard you singing.")
    }

    /// A heard word is one raw event, from the mic, that wakes the brain
    /// with its line, the core untold; and like a poke it doesn't while
    /// something needs you.
    func testAHeardWordReachesTheBrain() {
        let rig = CoreRig()
        let views = Fx(rig.pipeline.heard("good", at: rig.now)).views
        XCTAssertEqual(views.map(\.line), [#"Boop heard you say "good boy"."#])
        XCTAssertEqual(views.map(\.name), ["heard"])
        XCTAssertEqual(views.first?.facts["misheard"], .bool(false))
        XCTAssertTrue(views.allSatisfy(\.wakesBrain))
        XCTAssertEqual(rig.ruleActions, [], "the rules do nothing")
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        XCTAssertFalse(Fx(rig.pipeline.heard("dance", misheard: true, at: rig.now)).views.contains(where: \.wakesBrain),
                       "while something needs you, only what you say wakes the brain")
    }
}
