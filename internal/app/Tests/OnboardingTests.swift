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

    /// With no runtime (before the board, or one that couldn't start),
    /// where onboarding stands is saved straight into settings.json, with
    /// the rest of the settings kept, so a launch comes back to the act,
    /// and a finish stays finished.
    func testWithNoRuntimeTheActIsSavedStraightToSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var settings = AppSettings()
        settings.board = "b00p-54fe"
        try settings.save(to: dir)
        try Onboarding.save(.agents, runtime: nil, stateDir: dir)
        XCTAssertEqual(AppSettings.load(from: dir).onboarding, .agents)
        XCTAssertEqual(AppSettings.load(from: dir).board, "b00p-54fe")
        XCTAssertEqual(Onboarding.resume(isSetUp: true, saved: AppSettings.load(from: dir).onboarding), .agents)
        try Onboarding.save(nil, runtime: nil, stateDir: dir)
        XCTAssertNil(Onboarding.resume(isSetUp: true, saved: AppSettings.load(from: dir).onboarding), "finished")
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
    /// nothing found, does nothing. The button pairs it as the screen does.
    func testATapPairsTheBoardOnlyWhileLookingWithOneFound() {
        var progress = Onboarding.Progress(act: .body)
        XCTAssertEqual(progress.tapped(boardFound: true, button: false), .nothing, "not looking yet")
        progress.body = .looking
        XCTAssertEqual(progress.tapped(boardFound: false, button: false), .nothing, "nothing found")
        XCTAssertEqual(progress.body, .looking)
        XCTAssertEqual(progress.tapped(boardFound: true, button: false), .paired)
        XCTAssertEqual(progress.body, .joined)
        XCTAssertEqual(progress.tapped(boardFound: true, button: false), .nothing, "paired once")

        var pressed = Onboarding.Progress(act: .body)
        pressed.body = .looking
        XCTAssertEqual(pressed.tapped(boardFound: true, button: true), .paired)
    }

    /// The lessons: a tap on the screen does "Tap my screen", and only a
    /// press of the button does "Press my button", each once; the tap that
    /// paired the board counts as its own.
    func testEachLessonIsDoneByItsOwnTouch() {
        var paired = Onboarding.Progress(act: .body)
        paired.body = .looking
        _ = paired.tapped(boardFound: true, button: false)
        paired.move(to: .howTo)
        XCTAssertEqual(paired.lessons, [.tap])
        XCTAssertEqual(paired.tapped(boardFound: true, button: false), .nothing, "the screen again isn't the button")
        XCTAssertEqual(paired.lessons, [.tap])
        XCTAssertEqual(paired.tapped(boardFound: true, button: true), .lesson(.button))
        XCTAssertEqual(paired.lessons, [.tap, .button])
        XCTAssertEqual(paired.tapped(boardFound: true, button: true), .nothing)

        var later = Onboarding.Progress(act: .howTo)
        XCTAssertEqual(later.tapped(boardFound: true, button: true), .lesson(.button), "in either order")
        XCTAssertEqual(later.tapped(boardFound: true, button: false), .lesson(.tap))
        XCTAssertEqual(later.lessons, [.tap, .button])
    }

    /// The rule: Back into the board's act after it was skipped, by
    /// "I don't have my Boop yet" or by a launch past it, starts it again
    /// from "Plug me in", never a skipped act with nothing to show.
    func testBackIntoTheBoardAfterSkippingItStartsItAgain() {
        var skipped = Onboarding.Progress(act: .body)
        skipped.body = .skipped
        skipped.move(to: .howTo)
        skipped.move(to: .body)
        XCTAssertEqual(skipped.body, .intro)

        var relaunched = Onboarding.Progress(act: .agents)
        relaunched.move(to: .howTo)
        XCTAssertEqual(relaunched.body, .skipped, "past the board it stays skipped")
        relaunched.move(to: .body)
        XCTAssertEqual(relaunched.body, .intro)

        var joined = Onboarding.Progress(act: .body)
        joined.body = .joined
        joined.move(to: .howTo)
        joined.move(to: .body)
        XCTAssertEqual(joined.body, .joined, "a paired board stays paired")
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
