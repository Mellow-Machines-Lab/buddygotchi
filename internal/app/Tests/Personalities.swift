import Foundation
import XCTest
@testable import BoopKit

/// Boop's two personalities by name (characters/boop/character.json), which
/// the tests run on: Boop's pack is the one they load.
extension Personality {
    static let boop = Personality(rawValue: "boop")!
    static let chatter = Personality(rawValue: "chatter")!
}

/// The tests that need Boop's pack (its goldens, evals, voice, wording and
/// moods) skip when another pack is chosen (characters/CHARACTER.md §11).
/// Each such class calls this in its setUpWithError.
func requireBoopsPack() throws {
    try XCTSkipUnless(CharacterPack.active.id == "boop", "needs Boop's character pack, and another is chosen")
}
