import Foundation

/// The buddy: a board running one character pack, under the name you
/// gave it.
public struct Buddy: Sendable {
    /// Its pack's id.
    public let id: String
    /// Its character, under the buddy's own name.
    public let pack: CharacterPack

    public init(id: String, pack: CharacterPack) {
        self.id = id
        self.pack = pack
    }

    /// The process's character, as Boop runs.
    public static func only(_ pack: CharacterPack = .active) -> Buddy { Buddy(id: pack.id, pack: pack) }

    /// What it's called.
    public var name: String { pack.name }
}
