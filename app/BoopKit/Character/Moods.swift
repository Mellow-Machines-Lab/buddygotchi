import Foundation

extension CharacterPack {
    /// Every character's moods (characters/CHARACTER.md §5): a pack has
    /// each of these, and no other. How the moods connect, what each means
    /// and how each looks and sounds is the pack's own. This is the one
    /// list: characters/charactergen.py reads it from this file to check
    /// the packs, so keep it one literal of quoted names.
    public static let universalMoods = [
        "calm", "comfy", "lazy", "bored", "pleased", "happy", "excited", "curious", "engaged", "determined", "proud",
        "mischievous", "shy", "uncomfortable", "annoyed", "irritated", "grumpy", "angry", "disappointed", "sad", "crying",
        "whiny", "wounded", "uneasy", "scared", "frightened", "surprised", "stunned", "speechless", "amused", "hopeful",
        "relieved", "confused", "baffled", "skeptical", "embarrassed", "affectionate", "lonely", "tired", "exhausted",
        "overwhelmed", "disgusted",
    ]
}
