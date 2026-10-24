import AgentHooks
import Foundation
import XCTest
@testable import BoopKit

final class OnboardingTests: XCTestCase {
    /// The rule: an unnamed Boop starts from the top; a quit after naming
    /// resumes at the saved act; a named Boop with none saved is done,
    /// every Boop named before onboarding existed included. A saved act
    /// from before naming means nothing.
    func testWhereALaunchStarts() {
        XCTAssertEqual(Onboarding.resume(isSetUp: false, saved: nil), .hello)
        XCTAssertEqual(Onboarding.resume(isSetUp: false, saved: .agents), .hello, "no memory: from the top")
        XCTAssertEqual(Onboarding.resume(isSetUp: true, saved: .agents), .agents)
        XCTAssertEqual(Onboarding.resume(isSetUp: true, saved: .body), .body)
        XCTAssertNil(Onboarding.resume(isSetUp: true, saved: nil), "done, or named before onboarding")
        XCTAssertNil(Onboarding.resume(isSetUp: true, saved: .hello))
    }

    /// Back never goes past the board: the name is for keeps once given.
    func testActsGoForwardAndBackButNotBehindTheName() {
        XCTAssertEqual(Onboarding.Act.allCases.map(\.rawValue),
                       ["hello", "whatIDo", "makeMeYours", "body", "howTo", "agents", "smallThings", "finale"])
        XCTAssertEqual(Onboarding.Act.hello.next, .whatIDo)
        XCTAssertNil(Onboarding.Act.finale.next)
        XCTAssertNil(Onboarding.Act.hello.back)
        XCTAssertEqual(Onboarding.Act.makeMeYours.back, .whatIDo)
        XCTAssertNil(Onboarding.Act.body.back)
        XCTAssertEqual(Onboarding.Act.agents.back, .howTo)
        XCTAssertEqual(Onboarding.Act.allCases.filter(\.afterNaming), [.body, .howTo, .agents, .smallThings, .finale])
    }

    func testTheSavedActRoundTripsAndOlderSettingsHaveNone() throws {
        var settings = AppSettings()
        settings.onboarding = .howTo
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.onboarding, .howTo)
        let older = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"personality":"boop","volume":6}"#.utf8))
        XCTAssertNil(older.onboarding)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"onboarding":"somethingNew"}"#.utf8))
        XCTAssertNil(unknown.onboarding, "an act this version doesn't know is none")
    }
}

final class OnboardingProgressTests: XCTestCase {
    /// A launch partway through: past the board it's skipped, past the
    /// agents they're connected; before, neither.
    func testALaunchPartwayThroughStartsAsItShould() {
        XCTAssertEqual(Onboarding.Progress(act: .body).body, .intro)
        XCTAssertEqual(Onboarding.Progress(act: .howTo).body, .skipped)
        XCTAssertFalse(Onboarding.Progress(act: .agents).connected)
        XCTAssertTrue(Onboarding.Progress(act: .smallThings).connected)
    }

    /// The rule for pairing: a tap pairs the board only in act 4, while
    /// looking, with a board found; a tap before "Look for me", or with
    /// nothing found, does nothing.
    func testATapPairsTheBoardOnlyWhileLookingWithOneFound() {
        var progress = Onboarding.Progress(act: .body)
        XCTAssertEqual(progress.tapped(boardFound: true), .nothing, "not looking yet")
        progress.body = .looking
        XCTAssertEqual(progress.tapped(boardFound: false), .nothing, "nothing found")
        XCTAssertEqual(progress.body, .looking)
        XCTAssertEqual(progress.tapped(boardFound: true), .paired)
        XCTAssertEqual(progress.body, .joined)
        XCTAssertEqual(progress.tapped(boardFound: true), .nothing, "paired once")
    }

    /// The lessons: the pairing tap counts as the first, the next tap or
    /// press does the button, and more do nothing. Without pairing, the
    /// first tap is the tap lesson.
    func testTheLessonsAreDoneOnTheBoardInOrder() {
        var paired = Onboarding.Progress(act: .body)
        paired.body = .looking
        _ = paired.tapped(boardFound: true)
        paired.move(to: .howTo)
        XCTAssertEqual(paired.lessons, [.tap])
        XCTAssertEqual(paired.tapped(boardFound: true), .lesson(.button))
        XCTAssertEqual(paired.lessons, [.tap, .button])
        XCTAssertEqual(paired.tapped(boardFound: true), .nothing)

        var later = Onboarding.Progress(act: .howTo)
        XCTAssertEqual(later.tapped(boardFound: true), .lesson(.tap))
        XCTAssertEqual(later.tapped(boardFound: true), .lesson(.button))
    }

    /// The live hello: only in act 6, once connected, and only the first.
    func testOnlyTheFirstHookAfterConnectingIsTheHello() {
        var progress = Onboarding.Progress(act: .agents)
        XCTAssertFalse(progress.heard("claude"), "not connected yet")
        progress.connected = true
        XCTAssertTrue(progress.heard("codex"))
        XCTAssertFalse(progress.heard("claude"))
        XCTAssertEqual(progress.heard, "codex")
        var elsewhere = Onboarding.Progress(act: .finale)
        XCTAssertFalse(elsewhere.heard("claude"))
    }
}
