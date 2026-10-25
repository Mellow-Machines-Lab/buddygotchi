import Foundation
import XCTest
@testable import BoopKit

/// The engine's tests run on whichever pack is chosen. The few that check a
/// pack's own content (Boop's evals, goldens and 42 moods, Pixel's mood
/// graph) need that pack, and skip when another is chosen.
func requirePack(_ ids: String...) throws {
    try XCTSkipUnless(ids.contains(CharacterPack.active.id),
                      "needs the \(ids.joined(separator: " or ")) character pack, and \(CharacterPack.active.id) is chosen")
}

/// The chosen pack's creature's name, as the engine writes it in the lines
/// the tests check.
var creature: String { CharacterPack.active.name }

/// The tests that play recorded takes need a pack with a voice
/// (characters/CHARACTER.md §8), and skip without one.
func requireVoice() throws {
    try XCTSkipUnless(!Take.all.isEmpty, "needs a character pack with a voice")
}

/// The brain's questions, in order: a pack with no voice is never asked
/// what to say.
var askedKeys: [String] {
    ["mood", "react.mood", "react.animation", "react.loops"] + (Take.all.isEmpty ? [] : ["say.feeling", "say.about", "say.kind"])
}
