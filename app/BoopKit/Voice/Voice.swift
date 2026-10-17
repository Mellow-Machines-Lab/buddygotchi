import Foundation

/// Boop's voice: the recorded takes the board has, and what a
/// reaction says. The only code that knows what Boop can say. The brain
/// answers how Boop feels and what NOW is about, and a kind; the face picks
/// the mood; Voice finds a take for each answer that plays in that mood and
/// joins them into a `say` of at most two: the feeling, then the topic.
/// Which moods a take plays in is the pack's table's to say; Voice never
/// borrows one from another mood.
public enum Voice {
    /// The pause between a `say`'s two takes, in milliseconds.
    public static let joinGapMs = 180
    /// The longest `say` of two takes, gap included; a longer pair keeps
    /// only its first.
    public static let maxSayMs = 2800

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

    /// The take one answer says: `part`'s `meaning`,
    /// that plays in the `face`'s mood, fit for the turn's `finish` (a
    /// success take only on a success, a swear only on a failure), of the
    /// nearest kind to `kind` that has one, at random, and not one whose
    /// text is in `avoiding` (the last `say`'s) when another fits: the bank
    /// has some words recorded twice in one mood, and most in several.
    /// Nil when none does.
    static func take(_ part: Take.Part, meaning: String, kind: Take.Kind, face: String, finish: String?,
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

    /// What a reaction says: the feeling's take, then the
    /// topic's, each of the nearest kind to `kind` and in the face's mood.
    /// Either may be missing. A phrase plays alone: with one of the two, the
    /// feeling's take, unless a phrase was asked for and only the topic's is
    /// one. The first take also plays alone when the two would run past
    /// `maxSayMs`.
    public static func say(feeling: String?, about: String?, kind: Take.Kind, face: String, finish: String?,
                            avoiding: Set<String> = [], in pack: CharacterPack = .active, rng: inout SplitMix64) -> [Take] {
        let first = feeling.flatMap {
            take(.feeling, meaning: $0, kind: kind, face: face, finish: finish, avoiding: avoiding, in: pack, rng: &rng)
        }
        let second = about.flatMap {
            take(.about, meaning: $0, kind: kind, face: face, finish: finish, avoiding: avoiding, in: pack, rng: &rng)
        }
        guard let first else { return second.map { [$0] } ?? [] }
        guard let second else { return [first] }
        if first.kind == .phrase || second.kind == .phrase {
            return [kind == .phrase && first.kind != .phrase ? second : first]
        }
        return first.ms + Self.joinGapMs + second.ms <= Self.maxSayMs ? [first, second] : [first]
    }
}
