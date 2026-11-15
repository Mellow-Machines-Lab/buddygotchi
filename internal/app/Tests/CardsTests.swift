@testable import BoopKit
import AgentHooks
import Foundation
import LinkKit
import XCTest

/// The cards agents hand Boop (`Card`, `Cards`, `Core.card`): what a card
/// keeps, which one Boop holds, how long, and what the board is sent.
final class CardsTests: XCTestCase {
    func status(_ doing: String, step: Int? = nil, of: Int? = nil, minutes: Int? = nil) -> Card {
        Card(kind: .status, text: doing, step: step, of: of, minutes: minutes)
    }

    func result(_ headline: String, detail: String? = nil, link: String? = nil) -> Card {
        Card(kind: .result, text: headline, detail: detail, link: link)
    }

    // MARK: What a card keeps

    /// The main thing keeps 24 characters and the small line 28, cut at a
    /// word; a card with no words is no card.
    func testACardIsHeldToItsLimits() throws {
        XCTAssertEqual(Card.textMost, 24)
        XCTAssertEqual(Card.detailMost, 28)
        let made = Card.make(.result, ["headline": "Blocked: needs token and VPN",
                                                     "detail": "integration tests need a token and the VPN"])
        let long = try XCTUnwrap(made)
        XCTAssertEqual(long.text, "Blocked: needs token..", "cut at a word, marked as the board marks a cut")
        XCTAssertEqual(Card.make(.result, ["headline": "Done; integration test failed"])?.text, "Done; integration test..")
        XCTAssertEqual(Card.make(.status, ["doing": "fixing “it”… now"])?.text, "fixing \"it\"... now", "as the board's fonts draw it")
        XCTAssertLessThanOrEqual(long.text.count, 24)
        XCTAssertLessThanOrEqual(long.detail?.count ?? 99, 28)
        XCTAssertEqual(Card.make(.status, ["doing": "fixing\nthe   nav"])?.text, "fixing the nav", "one line")
        XCTAssertNil(Card.make(.status, ["doing": "  "]))
        XCTAssertNil(Card.make(.status, [:]))
        XCTAssertNil(Card.make(.result, ["detail": "no headline"]))
    }

    /// A step needs both its numbers, in order; a guess outside 0 to 600
    /// minutes is left out.
    func testNumbersOutsideTheirRangeAreLeftOut() {
        let whole = Card.make(.status, ["doing": "x", "step": 2, "of": 5, "minutes_left": 3.6])
        XCTAssertEqual([whole?.step, whole?.of, whole?.minutes], [2, 5, 4])
        XCTAssertNil(Card.make(.status, ["doing": "x", "step": 2])?.step)
        XCTAssertNil(Card.make(.status, ["doing": "x", "step": 6, "of": 5])?.of)
        XCTAssertNil(Card.make(.status, ["doing": "x", "minutes_left": 5000])?.minutes)
        XCTAssertNil(Card.make(.status, ["doing": "x", "minutes_left": -1])?.minutes)
    }

    /// A tap may open a web page or an absolute path, and nothing else.
    func testOnlyAWebPageOrAPathIsALink() {
        func link(_ s: String) -> String? { Card.make(.result, ["headline": "done", "link": s])?.link }
        XCTAssertEqual(link("https://example.com/pull/12"), "https://example.com/pull/12")
        XCTAssertEqual(link("/tmp/report.html"), "/tmp/report.html")
        XCTAssertEqual(link("~/notes.md"), "~/notes.md")
        for bad in ["textkit/wordcount.py", "file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "https://",
                    "https://example.com/" + String(repeating: "a", count: Card.linkMost)] {
            XCTAssertNil(link(bad), bad)
        }
        XCTAssertFalse(CardTool.open("textkit/wordcount.py"))
        XCTAssertFalse(CardTool.open("/nowhere/that/exists/\(UUID().uuidString)"))
    }

    /// What the tool server sends is what the runtime reads back.
    func testTheToolsLineCarriesTheCardAndItsProcess() throws {
        let card = try XCTUnwrap(Card.make(.status, ["doing": "running the tests", "step": 2, "of": 5, "minutes_left": 4]))
        let data = CardTool.line(card, agent: "claude", pid: 4242, started: 7)
        XCTAssertEqual(data.last, 0x0A)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sent = try XCTUnwrap(object["card"] as? [String: Any])
        XCTAssertEqual(Card.make(.status, CardTool.arguments(sent)), card)
        XCTAssertEqual((object["process"] as? [String: Any])?["pid"] as? Int, 4242)
        XCTAssertNil(HookLine.decode(data), "never taken for a hook")
    }

    // MARK: The small line

    /// The agent's guess is counted down in whole minutes as it stands,
    /// never corrected: left, "any minute now", then over.
    func testTheGuessCountsDownAndRunsOver() {
        var cards = Cards()
        cards.status(status("running the tests", step: 2, of: 5, minutes: 2), for: "a", at: 0)
        XCTAssertEqual(cards.shown("a", at: 0)?.small, "2 of 5 · 2 min left")
        XCTAssertEqual(cards.shown("a", at: 59_000)?.small, "2 of 5 · 2 min left")
        XCTAssertEqual(cards.shown("a", at: 60_000)?.small, "2 of 5 · 1 min left")
        XCTAssertEqual(cards.shown("a", at: 120_000)?.small, "2 of 5 · any minute now")
        XCTAssertEqual(cards.shown("a", at: 120_000)?.over, false)
        XCTAssertEqual(cards.shown("a", at: 300_000)?.small, "2 of 5 · 3 min over")
        XCTAssertEqual(cards.shown("a", at: 300_000)?.over, true)
        // The same card again, as agents send it, doesn't restart the count.
        cards.status(status("running the tests", step: 2, of: 5, minutes: 2), for: "a", at: 60_000)
        XCTAssertEqual(cards.shown("a", at: 60_000)?.small, "2 of 5 · 1 min left")
        // With neither, there's no small line.
        cards.status(status("reading the code"), for: "b", at: 0)
        XCTAssertNil(cards.shown("b", at: 0)?.small)
    }

    /// A result's small line is its detail, or else how the first guess did.
    func testAResultSaysHowTheGuessDid() {
        var cards = Cards()
        cards.status(status("fixing", minutes: 5), for: "a", at: 0)
        cards.result(result("nav overflow fixed"), for: "a", at: 700_000)
        cards.turnEnded("a", away: false, at: 12 * 60_000)
        XCTAssertEqual(cards.shown("a", at: 12 * 60_000)?.small, "said 5 min, took 12")
        cards.status(status("fixing", minutes: 5), for: "b", at: 0)
        cards.result(result("fixed", detail: "3 files"), for: "b", at: 1000)
        cards.turnEnded("b", away: false, at: 2000)
        XCTAssertEqual(cards.shown("b", at: 2000)?.small, "3 files")
    }

    // MARK: Which card, and how long

    /// A result shows for `resultMs` (15 s) after its turn and goes by
    /// itself; one that ended while you were away waits for you.
    func testAResultGoesByItselfAndWaitsWhileYouAreAway() {
        XCTAssertEqual(Cards.resultMs, 15_000)
        var cards = Cards()
        cards.result(result("done"), for: "a", at: 0)
        XCTAssertEqual(cards.showing(in: ["a"], at: 0), [], "not before the turn ends")
        cards.turnEnded("a", away: true, at: 1000)
        XCTAssertEqual(cards.showing(in: ["a"], at: 600_000), [], "away")
        cards.youAreBack(at: 600_000)
        XCTAssertEqual(cards.showing(in: ["a"], at: 614_000), ["a"])
        XCTAssertEqual(cards.showing(in: ["a"], at: 615_000), [])
        cards.tidy(at: 615_000)
        XCTAssertNil(cards.shown("a", at: 615_000))
    }

    /// Boop holds the card that changed last, once the one in its hands has
    /// had `holdMs` (8 s); a swipe keeps your choice for `pinMs` (2 min).
    func testTheNewestChangeTakesTheHandsAfterTheHoldAndASwipePins() {
        XCTAssertEqual(Cards.holdMs, 8000)
        XCTAssertEqual(Cards.pinMs, 120_000)
        var cards = Cards()
        let order = ["a", "b", "c"]
        cards.status(status("one"), for: "a", at: 0)
        cards.refocus(order, at: 0)
        XCTAssertEqual(cards.focus, "a")
        cards.status(status("two"), for: "b", at: 3000)
        cards.refocus(order, at: 3000)
        XCTAssertEqual(cards.focus, "a", "a's card has had 3 s")
        cards.refocus(order, at: 8000)
        XCTAssertEqual(cards.focus, "b")
        // The card in its hands changing isn't a reason to leave it.
        cards.status(status("two, still"), for: "b", at: 30_000)
        cards.refocus(order, at: 30_000)
        XCTAssertEqual(cards.focus, "b")
        cards.status(status("three"), for: "c", at: 31_000)
        cards.swipe(by: -1, among: order, at: 40_000)
        XCTAssertEqual(cards.focus, "a")
        cards.refocus(order, at: 100_000)
        XCTAssertEqual(cards.focus, "a", "pinned")
        cards.status(status("three, again"), for: "c", at: 161_000)
        cards.refocus(order, at: 161_000)
        XCTAssertEqual(cards.focus, "c", "the pin has run out")
        cards.swipe(by: 1, among: order, at: 170_000)
        XCTAssertEqual(cards.focus, "a", "round to the first")
    }

    // MARK: Through the core

    /// A status shows on the `state` while its turn runs, goes under
    /// something that needs you and comes back after it.
    func testAStatusCardShowsWhileItsTurnRunsAndUnderNothingThatNeedsYou() throws {
        let rig = CoreRig()
        rig.pipeline.card(status("fixing the overflow", step: 2, of: 5, minutes: 4), process: nil, at: rig.now)
        XCTAssertNil(rig.state.card, "no session at work: nobody's card")
        rig.send(.turnStart)
        rig.pipeline.card(status("fixing the overflow", step: 2, of: 5, minutes: 4), process: nil, at: rig.now)
        let card = try XCTUnwrap(rig.state.card)
        XCTAssertEqual([card.text, card.small], ["fixing the overflow", "2 of 5 · 4 min left"])
        XCTAssertEqual([card.index, card.count], [1, 1])
        XCTAssertFalse(card.result)
        XCTAssertTrue(rig.state.jsonLine.contains(#""card":{"#), rig.state.jsonLine)
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.card, "fixing the overflow, 2 of 5 · 4 min left")
        rig.send(.needsYou, tool: "Bash")
        XCTAssertNil(rig.state.card)
        rig.send(.activity, tool: "Bash")
        XCTAssertNotNil(rig.state.card)
    }

    /// The result waits for the turn's end, shows 15 s with nothing to put
    /// away, and the next prompt clears it at once.
    func testAResultShowsAfterTheFinishAndNeverNeedsDismissing() throws {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.pipeline.card(status("fixing the overflow"), process: nil, at: rig.now)
        rig.wait(5000)
        rig.pipeline.card(result("nav overflow fixed", detail: "3 files, 212 tests green"), process: nil, at: rig.now)
        XCTAssertEqual(rig.state.card?.text, "fixing the overflow", "the result waits for the finish")
        rig.send(.turnEnd)
        let card = try XCTUnwrap(rig.state.card)
        XCTAssertTrue(card.result)
        XCTAssertEqual([card.text, card.small], ["nav overflow fixed", "3 files, 212 tests green"])
        rig.wait(Cards.resultMs - 1000)
        XCTAssertNotNil(rig.state.card)
        rig.wait(1000)
        XCTAssertNil(rig.state.card)

        rig.send(.turnStart)
        rig.pipeline.card(result("again"), process: nil, at: rig.now)
        rig.send(.turnEnd)
        XCTAssertNotNil(rig.state.card)
        rig.send(.turnStart)
        XCTAssertNil(rig.state.card, "the next prompt")
        rig.send(.turnEnd)
        XCTAssertNil(rig.state.card, "a turn with no result card shows none")
    }

    /// With two sessions at work a card is its process's session's; one
    /// from a process nobody knows is dropped. A swipe moves to the other.
    func testACardGoesToItsProcessesSessionAndASwipeMoves() throws {
        let rig = CoreRig()
        func start(_ session: String, pid: Int64) {
            var e = rig.event(.turnStart, session: session, project: session)
            e.data["process"] = .object(["pid": .int(pid), "started": 1])
            rig.send(e)
        }
        start("s1", pid: 11)
        start("s2", pid: 22)
        rig.pipeline.card(status("lost"), process: AgentProcess(pid: 33, started: 1), at: rig.now)
        rig.pipeline.card(status("lost too"), process: nil, at: rig.now)
        XCTAssertNil(rig.state.card)
        rig.pipeline.card(status("one"), process: AgentProcess(pid: 11, started: 1), at: rig.now)
        rig.wait(1000)
        rig.pipeline.card(status("two"), process: AgentProcess(pid: 22, started: 1), at: rig.now)
        XCTAssertEqual(rig.state.card?.text, "one")
        XCTAssertEqual(rig.state.card?.count, 2)
        let first = try XCTUnwrap(rig.state.card?.index)
        rig.pipeline.swipeCard(by: 1, at: rig.now)
        XCTAssertEqual(rig.state.card?.text, "two")
        XCTAssertNotEqual(rig.state.card?.index, first)
        rig.pipeline.swipeCard(by: 1, at: rig.now)
        XCTAssertEqual(rig.state.card?.text, "one")
    }

    /// A tap opens the result's link, or with none the session's thread,
    /// and with no card nothing.
    func testATapOpensTheLinkOrTheThread() {
        let rig = CoreRig()
        XCTAssertFalse(Fx(rig.pipeline.tapCard(at: rig.now)).contains { if case .open = $0 { true } else { false } })
        rig.send(.turnStart)
        rig.pipeline.card(status("deploying"), process: nil, at: rig.now)
        let onStatus = Fx(rig.pipeline.tapCard(at: rig.now))
        XCTAssertTrue(onStatus.contains { if case .open(let t) = $0 { t.session == "s1" } else { false } })
        XCTAssertEqual(rig.pipeline.transcript.events.last { $0.isAction }?.action, Core.openThread)
        rig.pipeline.card(result("preview deployed", link: "https://preview.example/build-1"), process: nil, at: rig.now)
        rig.send(.turnEnd)
        let onResult = Fx(rig.pipeline.tapCard(at: rig.now))
        XCTAssertTrue(onResult.contains(.openLink("https://preview.example/build-1")))
        let did = rig.pipeline.transcript.events.last { $0.isAction }
        XCTAssertEqual(did?.action, Core.openLink)
        XCTAssertFalse(did?.jsonLine.contains("preview.example") ?? true, "the link stays out of the log")
    }

    /// The longest card still fits the board's line, and no line for the
    /// brain carries a card's words: they're the agent's, for the screen.
    func testTheLongestCardFitsAndItsWordsStayFromTheBrain() throws {
        let rig = CoreRig()
        rig.send(.turnStart, project: String(repeating: "p", count: 40))
        let words = String(repeating: "W", count: Card.textMost)
        rig.pipeline.card(status(words, step: 99, of: 99, minutes: 600), process: nil, at: rig.now)
        XCTAssertTrue(rig.state.fits)
        XCTAssertEqual(rig.state.card?.text, words)
        XCTAssertLessThan(rig.state.jsonLine.utf8.count, Wire.maxLine)
        XCTAssertEqual(Wire.maxLine, 512)
        let log = rig.pipeline.transcript.view(now: rig.now)
        let lines = log.events.compactMap { rig.view.line($0, log) }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertFalse(lines.contains { "\($0)".contains(words) })
        XCTAssertTrue(log.events.contains { $0.type == .card && $0["text"]?.string == words }, "but the transcript has it")
    }
}
