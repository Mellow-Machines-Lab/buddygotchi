import Foundation

/// The buddy: a board running one character pack, under the name you
/// gave it.
public struct Buddy: Sendable {
    /// Its character, under the buddy's own name.
    public let pack: CharacterPack

    /// `pack` as the buddy: the process's character, as Boop runs.
    public init(_ pack: CharacterPack = .active) { self.pack = pack }

    /// What it's called.
    public var name: String { pack.name }
}
