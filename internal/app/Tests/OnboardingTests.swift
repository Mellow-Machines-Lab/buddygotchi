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
