import Foundation

/// Boop's voice: the recorded takes the board has, and what a
/// reaction says. The only code that knows what Boop can say. A rule says
/// what a Moment says (a skit's takes, a reply's own words, the hello at a
/// lock), how big the moment is picks the kind, and the face picks the
/// mood; Voice finds a take of it that plays in that mood. Which moods a
/// take plays in is the pack's table's to say; Voice never borrows one from
/// another mood.
public enum Voice {
    /// Every meaning of `part` that has a take, each once.
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

    /// What a reaction says: `part`'s `meaning`,
    /// that plays in the `face`'s mood, fit for the turn's `finish` (a
    /// success take only on a success, a swear only on a failure), of the
    /// nearest kind to `kind` that has one, at random, and not one whose
    /// text is in `avoiding` (the last says', the newest first) when another
    /// fits: the bank has some words recorded twice in one mood, and most in
    /// several. With every one said lately, the one said longest ago. None
    /// in `never`, whatever else fits. With a `text` the face has a take of,
    /// that one, whatever its kind. Nil when none fits.
    public static func take(_ part: Take.Part, meaning: String, kind: Take.Kind, face: String, finish: String?,
                            avoiding: [String] = [], never: Set<String> = [], text: String? = nil, in pack: CharacterPack = .active,
                            rng: inout SplitMix64) -> Take? {
        let fit = Take.all(in: pack).filter {
            $0.part == part && $0.meaning == meaning && $0.moods.contains(face) && ($0.finish == nil || $0.finish == finish)
                && !never.contains($0.text)
        }
        let picked = fit.filter { $0.text == text }
        if !picked.isEmpty { return picked[rng.int(in: 0...(picked.count - 1))] }
        for k in Self.order(kind) {
            let pool = fresh(fit.filter { $0.kind == k }, avoiding: avoiding)
            if !pool.isEmpty { return pool[rng.int(in: 0...(pool.count - 1))] }
        }
        return nil
    }

    /// The texts `take` picks among for `part`'s `meaning`, in any face, of
    /// the nearest kind to `kind` that has one: each once, those not said
    /// lately (`avoiding`, the newest first) first, then the one said
    /// longest ago first, at most `limit`. What a brain may choose from
    /// before the face is known.
    public static func texts(_ part: Take.Part, meaning: String, kind: Take.Kind, finish: String?, avoiding: [String] = [],
                             never: Set<String> = [], limit: Int, in pack: CharacterPack = .active) -> [String] {
        let fit = Take.all(in: pack).filter {
            $0.part == part && $0.meaning == meaning && ($0.finish == nil || $0.finish == finish) && !never.contains($0.text)
        }
        guard let pool = Self.order(kind).lazy.map({ k in fit.filter { $0.kind == k } }).first(where: { !$0.isEmpty }) else { return [] }
        let texts = pool.map(\.text).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let unsaid = texts.filter { !avoiding.contains($0) }
        let said = texts.filter { avoiding.contains($0) }.sorted { avoiding.firstIndex(of: $0)! > avoiding.firstIndex(of: $1)! }
        return Array((unsaid + said).prefix(limit))
    }

    /// Those of `pool` not said lately (`avoiding`, the newest first), or
    /// with all of them said lately, those said longest ago.
    static func fresh(_ pool: [Take], avoiding: [String]) -> [Take] {
        let unsaid = pool.filter { !avoiding.contains($0.text) }
        if !unsaid.isEmpty { return unsaid }
        let oldest = pool.compactMap { avoiding.firstIndex(of: $0.text) }.max()
        return pool.filter { avoiding.firstIndex(of: $0.text) == oldest }
    }

    /// The pause between a `say`'s two takes, in milliseconds, as the board
    /// plays it (firmware `kJoinGapMs`), and the longest `say` of two, the
    /// gap included.
    public static let joinGapMs = 180, maxSayMs = 2800
    /// How often a word gets a sound before it, in percent.
    public static let leadChance = 50

    /// A sound to say before `word`, now and then: a word or a swear gets
    /// one of the same meaning, performed in the same mood, that plays in
    /// the `face`'s mood and fits the `finish`, so "Ugh.... Broken" is one
    /// feeling said twice over, never two things. Not one whose text is in
    /// `avoiding` while another fits, nor one that makes the `say` longer
    /// than `maxSayMs`. Nil for any other take, or none that fits.
    public static func lead(before word: Take, face: String, finish: String?, avoiding: [String] = [],
                            in pack: CharacterPack = .active, rng: inout SplitMix64) -> Take? {
        guard word.kind == .word || word.kind == .swear else { return nil }
        let pool = Take.all(in: pack).filter {
            $0.kind == .sound && $0.part == word.part && $0.meaning == word.meaning && $0.moods.first == word.moods.first
                && $0.moods.contains(face) && ($0.finish == nil || $0.finish == finish) && $0.ms + joinGapMs + word.ms <= maxSayMs
        }
        guard !pool.isEmpty, rng.chance(leadChance) else { return nil }
        let fresh = fresh(pool, avoiding: avoiding)
        return fresh[rng.int(in: 0...(fresh.count - 1))]
    }
}
