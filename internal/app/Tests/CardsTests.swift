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
        let data = CardTool.line(card, process: AgentProcess(pid: 4242, started: 7))
        XCTAssertEqual(data.last, 0x0A)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let read = try XCTUnwrap(CardTool.read(object))
        XCTAssertEqual(read.card, card)
        XCTAssertEqual(read.process, AgentProcess(pid: 4242, started: 7))
        let result = Card(kind: .result, text: "preview deployed", detail: "build-4821", link: "https://example.com/b")
        XCTAssertEqual(CardTool.read(["card": "result", "args": result.args])?.card, result)
        XCTAssertNil(CardTool.read(["card": "status", "args": ["doing": " "]]), "held to the limits again")
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

    /// Boop holds the card of the agent you last prompted, and another
    /// agent's status never takes it; a swipe holds another until you
    /// prompt again.
    func testItHoldsWhoYouPromptedAndASwipeHoldsAnother() {
        var cards = Cards()
        let order = ["a", "b", "c"]
        for key in order { cards.turnStarted(key) }  // you prompted c last
        cards.status(status("one"), for: "a", at: 0)
        cards.refocus(cards.showing(in: order, at: 0), at: 0)
        XCTAssertEqual(cards.focus, "a", "the only card")
        cards.status(status("three"), for: "c", at: 1000)
        cards.refocus(cards.showing(in: order, at: 1000), at: 1000)
        XCTAssertEqual(cards.focus, "c", "who you prompted")
        for at in stride(from: Int64(2000), to: 600_000, by: 7000) {
            cards.status(status("one, at \(at)"), for: "a", at: at)
            cards.status(status("two, at \(at)"), for: "b", at: at)
            cards.refocus(cards.showing(in: order, at: at), at: at)
            XCTAssertEqual(cards.focus, "c", "the others' changes never take it")
        }
        cards.swipe(by: -1, among: cards.showing(in: order, at: 600_000), at: 600_000)
        XCTAssertEqual(cards.focus, "b")
        cards.status(status("three, again"), for: "c", at: 700_000)
        cards.refocus(cards.showing(in: order, at: 700_000), at: 700_000)
        XCTAssertEqual(cards.focus, "b", "held until you prompt or swipe")
        cards.swipe(by: 2, among: cards.showing(in: order, at: 710_000), at: 710_000)
        XCTAssertEqual(cards.focus, "a", "round past the end")
        cards.turnStarted("b")
        cards.status(status("two, anew"), for: "b", at: 720_000)
        cards.refocus(cards.showing(in: order, at: 720_000), at: 720_000)
        XCTAssertEqual(cards.focus, "b", "a new prompt")
    }

    /// Only results interrupt: each takes the card once, in the order they
    /// came, keeping it `holdMs` (8 s) before the next; then the card you
    /// were on comes back. One that waited out its 15 s is skipped.
    func testResultsInterruptOnceEachInTurn() {
        XCTAssertEqual(Cards.holdMs, 8000)
        var cards = Cards()
        let order = ["a", "b", "c", "d"]
        for key in order { cards.turnStarted(key); cards.status(status(key), for: key, at: 0) }
        cards.refocus(cards.showing(in: order, at: 0), at: 0)
        XCTAssertEqual(cards.focus, "d")
        for (key, at) in [("a", Int64(1000)), ("b", 1500), ("c", 2000)] {
            cards.result(result("\(key) done"), for: key, at: at)
            cards.turnEnded(key, away: false, at: at)
        }
        cards.refocus(cards.showing(in: order, at: 2000), at: 2000)
        XCTAssertEqual(cards.focus, "a", "the first to finish")
        cards.refocus(cards.showing(in: order, at: 9999), at: 9999)
        XCTAssertEqual(cards.focus, "a", "held 8 s")
        cards.refocus(cards.showing(in: order, at: 10_000), at: 10_000)
        XCTAssertEqual(cards.focus, "b")
        cards.refocus(cards.showing(in: order, at: 17_000), at: 17_000)
        XCTAssertEqual(cards.showing(in: order, at: 18_000), ["d"], "c waited out its 15 s: skipped")
        cards.tidy(at: 18_000)
        cards.refocus(cards.showing(in: order, at: 18_000), at: 18_000)
        XCTAssertEqual(cards.focus, "d", "back to who you prompted")
    }

    // MARK: Through the core

    /// A status is no card of words on the `state` any more: Boop holds a
    /// live picture of the work instead (`Core.picture`). Its words stay
    /// in the popover's row, and become the plan's step.
    func testAStatusIsNoCardOfWords() throws {
        let rig = CoreRig()
        rig.pipeline.card(status("fixing the overflow", step: 2, of: 5, minutes: 4), process: nil, at: rig.now)
        XCTAssertNil(rig.state.card, "no session at work: nobody's card")
        rig.send(.turnStart)
        rig.pipeline.card(status("fixing the overflow", step: 2, of: 5, minutes: 4), process: nil, at: rig.now)
        XCTAssertNil(rig.state.card)
        XCTAssertFalse(rig.state.jsonLine.contains(#""card":{"#), rig.state.jsonLine)
        XCTAssertEqual(rig.core.sessionList(at: rig.now).first?.card, "fixing the overflow, 2 of 5 · 4 min left")
    }

    /// The result waits for the turn's end, shows 15 s with nothing to put
    /// away, and the next prompt clears it at once.
    func testAResultShowsAfterTheFinishAndNeverNeedsDismissing() throws {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.pipeline.card(status("fixing the overflow"), process: nil, at: rig.now)
        rig.wait(5000)
        rig.pipeline.card(result("nav overflow fixed", detail: "3 files, 212 tests green"), process: nil, at: rig.now)
        XCTAssertNil(rig.state.card, "the result waits for the finish")
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
        // A status is no card of words on the board (Core.picture); which
        // session holds which card shows in the popover's rows and the focus.
        func card(_ project: String) -> String? { rig.core.sessionList(at: rig.now).first { $0.project == project }?.card }
        func focused() -> String? { rig.core.cards.focus.flatMap { rig.core.sessions[$0]?.project } }
        XCTAssertEqual([card("s1"), card("s2")], ["one", "two"])
        XCTAssertEqual(focused(), "s2", "s2's: you prompted it last")
        rig.pipeline.swipeCard(by: 1, at: rig.now)
        XCTAssertEqual(focused(), "s1")
        rig.pipeline.swipeCard(by: 1, at: rig.now)
        XCTAssertEqual(focused(), "s2")
    }

    /// A tap opens the result's link, or with none the session's thread,
    /// and with no card nothing.
    /// A drawer row's second line is its card's words while it has one.
    func testADrawerRowSaysItsCard() throws {
        let rig = CoreRig()
        rig.send(.turnStart, session: "s1", project: "landing")
        rig.send(.turnStart, session: "s2", project: "api")
        var e = rig.event(.turnStart, session: "s2", project: "api")
        e.data["process"] = .object(["pid": 22, "started": 1])
        rig.send(e)
        rig.pipeline.card(status("running the tests"), process: AgentProcess(pid: 22, started: 1), at: rig.now)
        rig.pipeline.drawer(open: true, at: rig.now)
        let list = try XCTUnwrap(rig.state.list)
        XCTAssertEqual(list.first { $0.title == "api" }?.project, "running the tests")
        XCTAssertEqual(list.first { $0.title == "landing" }?.project, "", "no card, no name: nothing under")
    }

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
        rig.pipeline.card(result(words, detail: String(repeating: "D", count: Card.detailMost)), process: nil, at: rig.now)
        rig.send(.turnEnd)
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
