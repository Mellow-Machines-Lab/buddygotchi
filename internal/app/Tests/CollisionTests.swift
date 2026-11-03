import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What plays, waits or drops when moments meet: a moment plays whole, then
/// the next (documentation/architecture.html, Collisions). The Mac's half is
/// here: how each kind of `do` asks to play. The board's half, what a greeting
/// holds back and what cuts it, is in firmware's test_behaviour.
final class CollisionTests: XCTestCase {
    private func answers(_ choices: [String: String]) -> Answers {
        choices.mapValues { Answer(choice: $0, probabilities: [$0: 1]) }
    }

    /// One moment from `react` about `about`, as the board is sent it.
    private func moment(_ about: Event, firstToday: Bool = false, told: [String]? = nil, occasion: String? = nil,
                        sign: String? = nil, dreams: [TaggedLine] = []) -> Moment? {
        var sent: Moment?
        var left = occasion
        let react = MomentOutput(queue: { m, _ in sent = m }, blocked: { nil }, speaks: { false }, dreams: dreams,
                                 line: { _ in
                                     var facts: [String: JSONValue] = firstToday ? [TranscriptView.firstTodayFact: true] : [:]
                                     if let told { facts["dream_tags"] = .array(told.map { .string($0) }) }
                                     return Line("", facts: facts)
                                 },
                                 occasion: { _ in defer { left = nil }; return left })
        var choices = [MomentOutput.emotionKey: "happy", MomentOutput.moveKey: "wake up", MomentOutput.sizeKey: "medium"]
        if let sign { choices[Signs.questionKey] = sign }
        _ = react.run(answers(choices), now: about, log: Transcript.log().view(now: about.at))
        return sent
    }

    private let back = Event(at: 1000, source: .mac, type: .presence, phase: .end, specificType: "unlocked")

    /// Pins the queue's three ways in: your own talking cuts in; a moment
    /// with something to read waits its turn (a greeting of the day, a wish
    /// met); one with nothing to read is dropped when busy.
    func testHowEachRuleMomentAsksToPlay() {
        XCTAssertEqual(BoopDevice.play(Moment(anim: BoopDevice.listening)), .now)
        XCTAssertEqual(BoopDevice.play(Moment(anim: "notice", sign: "Day 50!")), .next, "a day's greeting")
        XCTAssertEqual(BoopDevice.play(Moment(anim: Core.wishMet, sign: "thanks")), .next, "a wish met")
        XCTAssertEqual(BoopDevice.play(Moment(anim: "starting")), .ifFree, "a late rule moment is worse than none")
    }

    /// Pins how long each may wait: a moment 5 s, and a word forward, which
    /// was news only just now, 1.5 s.
    func testHowLongEachWaits() {
        XCTAssertEqual(BoopDevice.reactionTTL, 5000)
        XCTAssertEqual(BoopDevice.callTTL, 1500)
    }

    /// The first moment of your day, and the one that tells the dream, are
    /// greetings; any other isn't.
    func testWhatIsAGreeting() {
        XCTAssertEqual(moment(back, firstToday: true)?.greeting, true)
        XCTAssertEqual(moment(back, told: ["fond"])?.greeting, true)
        XCTAssertEqual(moment(back)?.greeting, false)
        XCTAssertEqual(moment(back, firstToday: true)?.args["greeting"], true)
        XCTAssertNil(moment(back)?.args["greeting"], "and it's on the wire only then")
    }

    /// A special day's sign is code's, on your first showing up, over the
    /// brain's: Jev still picks the feeling and the words.
    func testASpecialDaysSignIsCodes() {
        let dreams = TaggedLine.parse("- had a dream")
        XCTAssertEqual(moment(back, firstToday: true, occasion: "Day 50!")?.sign, "Day 50!")
        XCTAssertEqual(moment(back, firstToday: true, told: [], occasion: "Happy Halloween!", sign: "had a dream", dreams: dreams)?.sign,
                       "Happy Halloween!", "over the dream's")
        XCTAssertEqual(moment(back, firstToday: true, told: [], sign: "had a dream", dreams: dreams)?.sign, "had a dream", "an ordinary day")
        XCTAssertEqual(moment(back, occasion: "Day 50!")?.sign, nil, "only on your first showing up")
    }

    /// The wish and the ask wait: neither is offered at the telling, nor at
    /// any showing up: their moment is an idle check-in.
    func testTheWishAndTheAskWaitForAnIdleCheckIn() {
        let asks = TaggedLine.parse("- [wish pet] pet me?\n- [hat idle keeps] hat or bow? | hat | bow")
        let telling = MomentOutput(queue: { _, _ in }, blocked: { nil }, speaks: { false }, line: { _ in Line("", facts: ["dream_tags": .array([.string("fond")])]) }, asks: asks,
                                   askable: { _, _, questions in questions }, wishable: { _, _ in [.pet] })
        let log = Transcript.log().view(now: 0)
        XCTAssertTrue(telling.wishOptions(back, log).isEmpty)
        XCTAssertTrue(telling.askOptions(back, log).isEmpty)
        XCTAssertTrue(Asks.moment(back, log, mood: MoodOutput.choice(), untouchedMs: nil).isEmpty)
        let checkIn = Event(at: 1000, source: .boop, type: .checkIn, specificType: "check_in")
        XCTAssertEqual(Asks.moment(checkIn, log, mood: MoodOutput.choice(), untouchedMs: nil), ["idle"])
    }

    /// Bringing up a note: at an idle check-in only, the line low on the
    /// board, its word the pack's, its clip the look, the note the narration.
    func testBringingUpANote() throws {
        let felt = Memory.Felt(line: "u stay up late fridays", note: "You stay up late on Fridays.")
        var sent: Moment?
        var talk = Talk.normal
        let react = MomentOutput(queue: { m, _ in sent = m }, blocked: { nil }, speaks: { true }, talk: { talk }, felt: { _ in [felt] })
        let log = Transcript.log().view(now: 1000)
        let checkIn = Event(at: 1000, source: .boop, type: .checkIn, specificType: "check_in")
        let sign = try XCTUnwrap(react.questions(now: checkIn, log: log).first { $0.key == Signs.questionKey })
        XCTAssertTrue(sign.options.contains { $0.name == felt.line })
        XCTAssertNil(react.questions(now: back, log: log).first { $0.key == Signs.questionKey }?.options.first { $0.name == felt.line }, "at a check-in only")
        let result = react.run(answers([MomentOutput.emotionKey: "amused", MomentOutput.sizeKey: "small", MomentOutput.sayKey: "quiet", Signs.questionKey: felt.line]),
                               now: checkIn, log: log)
        let moment = try XCTUnwrap(sent)
        XCTAssertEqual(moment.sign, felt.line)
        XCTAssertTrue(moment.low)
        XCTAssertEqual(moment.clip, MomentOutput.rememberClip)
        XCTAssertNil(moment.reason, "the board shows the line")
        if let word = CharacterPack.active.rememberWord { XCTAssertEqual(moment.say?.text, word) }
        XCTAssertEqual(result?.facts["felt"], .string(felt.line))
        XCTAssertNil(result?.facts["musing"])
        XCTAssertEqual(result?.facts["reason"]?.string, "\(CharacterPack.active.name) is amused. \(CharacterPack.active.name) remembers you stay up late on Fridays.")
        talk = .quiet
        XCTAssertTrue(react.feltOptions(checkIn).isEmpty, "never on Quiet")
    }

    /// Pins the board's room: a note's line fits a low sign.
    func testALineFitsTheLowSign() {
        XCTAssertEqual(MemoryPipeline.signMax, 40)
    }

    /// Led by the day's count: with the dream, and with nothing to tell.
    func testTheNarrationLeadsWithTheDay() {
        XCTAssertEqual(Narration.day(41, leading: nil), Narration(cause: "Day 41.", fact: "day 41"))
        let dream = Narration(cause: "Boop dreamed about Tuesday: you fought the tests.", fact: "fought")
        XCTAssertEqual(Narration.day(41, leading: dream),
                       Narration(cause: "Day 41. Boop dreamed about Tuesday: you fought the tests.", fact: "day 41: fought"))
        XCTAssertEqual(Narration.day(41, leading: Narration(cause: "You came back.", fact: "you were away 8 h")).fact, "day 41", "too long for both")
    }

    /// The first time you show up on a Boop day is marked once: a back, or a
    /// touch; a prompt or an agent isn't you showing up, and 5:00 starts the
    /// next day.
    func testTheFirstTimeYouShowUpToday() {
        let rig = CoreRig()
        let first = { (fx: Fx) in events(fx).filter { $0.facts[TranscriptView.firstTodayFact] != nil }.count }
        rig.send(.turnStart, prompt: "good morning")
        XCTAssertEqual(first(rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))), 1)
        XCTAssertEqual(first(rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))), 0)
        rig.wait(26 * 3_600_000, every: 3_600_000)
        XCTAssertEqual(first(rig.poke()), 1)
    }
}
