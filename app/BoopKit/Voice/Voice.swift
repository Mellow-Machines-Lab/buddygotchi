import Foundation

/// Boop's voice: the recorded takes the board has, and what a
/// reaction says. The only code that knows what Boop can say. The brain
/// answers what Boop says (a feeling, a swear or what NOW is about) and how
/// big the moment is, which picks the kind; the face picks the mood; Voice
/// finds a take of it that plays in that mood. Which moods a take plays in
/// is the pack's table's to say; Voice never borrows one from another mood.
public enum Voice {
    /// Every answer to `part`'s question that has a take, each once.
    public static func answers(_ part: Take.Part) -> Set<String> {
        Set(Take.all.filter { $0.part == part }.map(\.meaning))
    }

    /// The kinds to try for `kind`, nearest first: the kind
    /// itself, then plainer and fancier by distance, plainer first; a
    /// swear only when one was asked for.
    static func order(_ kind: Take.Kind) -> [Take.Kind] {
        let all = Take.Kind.allCases
        let at = all.firstIndex(of: kind)!
        return all.indices.sorted { (abs($0 - at), $0 > at ? 1 : 0) < (abs($1 - at), $1 > at ? 1 : 0) }
            .map { all[$0] }.filter { $0 != .swear || kind == .swear }
    }

    /// What a reaction says, `say`'s answer: `part`'s `meaning`,
    /// that plays in the `face`'s mood, fit for the turn's `finish` (a
    /// success take only on a success, a swear only on a failure), of the
    /// nearest kind to `kind` that has one, at random, and not one whose
    /// text is in `avoiding` (the last `say`'s) when another fits: the bank
    /// has some words recorded twice in one mood, and most in several.
    /// Nil when none does.
    public static func take(_ part: Take.Part, meaning: String, kind: Take.Kind, face: String, finish: String?,
                            avoiding: Set<String> = [], in pack: CharacterPack = .active, rng: inout SplitMix64) -> Take? {
        let fit = Take.all(in: pack).filter {
            $0.part == part && $0.meaning == meaning && $0.moods.contains(face) && ($0.finish == nil || $0.finish == finish)
        }
        for k in Self.order(kind) {
            var pool = fit.filter { $0.kind == k }
            if pool.contains(where: { !avoiding.contains($0.text) }) { pool.removeAll { avoiding.contains($0.text) } }
            if !pool.isEmpty { return pool[rng.int(in: 0...(pool.count - 1))] }
        }
        return nil
    }
}
