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
    private func moment(_ about: Event, firstToday: Bool = false, told: [String]? = nil, daySign: String? = nil,
                        sign: String? = nil, dreams: [TaggedLine] = []) -> Moment? {
        var sent: Moment?
        let react = MomentOutput(queue: { m, _ in sent = m }, blocked: { nil }, speaks: { false }, dreams: dreams,
                                 line: { _ in
                                     var facts: [String: JSONValue] = firstToday ? [TranscriptView.firstTodayFact: true] : [:]
                                     if let told { facts["dream_tags"] = .array(told.map { .string($0) }) }
                                     if let daySign { facts[TranscriptView.daySignFact] = .string(daySign) }
                                     return Line("", facts: facts)
                                 })
        var choices = [MomentOutput.emotionKey: "happy"]
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
        XCTAssertEqual(BoopDevice.play(Moment(anim: Core.wishGone)), .ifFree, "a late rule moment is worse than none")
    }

    /// Pins how long each may wait: a moment 5 s, and a word forward, which
    /// was news only just now, 1.5 s.
    func testHowLongEachWaits() {
        XCTAssertEqual(BoopDevice.reactionTTL, 5000)
        XCTAssertEqual(BoopDevice.callTTL, 1500)
    }

    /// The first hello of your day, and the one that tells the dream, play
    /// whole; any other doesn't.
    func testWhichHelloPlaysWhole() {
        XCTAssertEqual(moment(back, firstToday: true)?.greeting, true)
        XCTAssertEqual(moment(back, told: ["fond"])?.greeting, true)
        XCTAssertEqual(moment(back)?.greeting, false)
        XCTAssertEqual(moment(back, firstToday: true)?.args["greeting"], true)
        XCTAssertNil(moment(back)?.args["greeting"], "and it's on the wire only then")
    }

    /// A special day's sign is code's, on your hello, over the brain's:
    /// Jev still picks the feeling and the words.
    func testASpecialDaysSignIsCodes() {
        let dreams = TaggedLine.parse("- had a dream")
        XCTAssertEqual(moment(back, firstToday: true, daySign: "Day 50!")?.sign, "Day 50!")
        XCTAssertEqual(moment(back, firstToday: true, told: [], sign: "had a dream", dreams: dreams)?.sign, "had a dream", "an ordinary day")
    }

    /// Pins a hello's one extra: the special day's sign, else the dream,
    /// else what happened while you were away (`MomentRule.Extra`).
    func testAHelloHasOneExtra() {
        let day: [String: JSONValue] = [TranscriptView.daySignFact: "Day 50!", "dream_tags": .array([.string("fond")]), TranscriptView.noticedFact: "While you were gone…"]
        XCTAssertEqual(MomentRule.Extra(facts: day), .day(sign: "Day 50!"))
        XCTAssertEqual(MomentRule.Extra(facts: ["dream_tags": .array([.string("fond")]), TranscriptView.noticedFact: "While…"]), .telling(tags: ["fond"]))
        XCTAssertEqual(MomentRule.Extra(facts: [TranscriptView.noticedFact: "While…"]), .whileAway("While…"))
        XCTAssertNil(MomentRule.Extra(facts: ["away_ms": 1]))
    }

    /// The idle beat waits: nothing of it is offered at a hello, the
    /// telling or not: its moment is an idle check-in.
    func testTheIdleBeatWaitsForAnIdleCheckIn() {
        let beat = IdleBeat.Candidate(.wish, signs: ["pet me?"], wish: .pet)
        let react = MomentOutput(queue: { _, _ in }, blocked: { nil }, speaks: { false }, idleBeat: { _, _, _ in [beat] })
        let log = Transcript.log().view(now: 0)
        XCTAssertTrue(react.beats(back, log).isEmpty)
        let checkIn = Event(at: 1000, source: .boop, type: .checkIn, specificType: "check_in")
        XCTAssertEqual(react.beats(checkIn, log).first?.signs, ["pet me?"])
    }

    /// Bringing up a note: at an idle check-in only, the line low on the
    /// board, its word the pack's, its clip the look, the note the narration.
    func testBringingUpANote() throws {
        let felt = Memory.Felt(line: "u stay up late fridays", note: "You stay up late on Fridays.")
        var sent: Moment?
        let react = MomentOutput(queue: { m, _ in sent = m }, blocked: { nil }, speaks: { true },
                                 idleBeat: { _, _, _ in [IdleBeat.Candidate(.remembered, signs: [felt.line], remembered: felt)] })
        let log = Transcript.log().view(now: 1000)
        let checkIn = Event(at: 1000, source: .boop, type: .checkIn, specificType: "check_in")
        let sign = try XCTUnwrap(react.questions(now: checkIn, log: log).first { $0.key == Signs.questionKey })
        XCTAssertTrue(sign.options.contains { $0.name == felt.line })
        XCTAssertNil(react.questions(now: back, log: log).first { $0.key == Signs.questionKey }?.options.first { $0.name == felt.line }, "at a check-in only")
        let result = react.run(answers([MomentOutput.emotionKey: "amused", MomentOutput.sayKey: "quiet", Signs.questionKey: felt.line]),
                               now: checkIn, log: log)
        let moment = try XCTUnwrap(sent)
        XCTAssertEqual(moment.sign, felt.line)
        XCTAssertTrue(moment.low)
        XCTAssertEqual(moment.clip, MomentOutput.rememberClip)
        XCTAssertNil(moment.reason, "the board shows the line")
        if let word = CharacterPack.active.rememberWord { XCTAssertEqual(moment.say?.text, word) }
        XCTAssertEqual(result?.facts["felt"], .string(felt.line))
        XCTAssertEqual(result?.facts[IdleBeat.fact], "remembered")
        XCTAssertEqual(result?.facts["reason"]?.string, "\(CharacterPack.active.name) is amused. \(CharacterPack.active.name) remembers you stay up late on Fridays.")
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
