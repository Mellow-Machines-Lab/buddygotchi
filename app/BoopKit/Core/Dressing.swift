import Foundation

/// Why the board looks as it does now, for the popover: each reason, first
/// every occasion Boop is celebrating today, then the night or the
/// morning, your prompt and the Friday, with what the board wears or
/// shows for it. It chooses
/// as the board does, from the same tags (firmware/src/render/tags.cpp's
/// outfitFor, eyewearFor and airFor): one hat, the first that fits, of a
/// witch hat at Halloween, a party hat, a nightcap at night and a bobble
/// hat in the winter holidays; on the gel, reading glasses for your
/// prompt, else shades on a Friday from noon short of night (off while it
/// shows a feeling, which the popover doesn't follow), neither while it
/// sleeps, and pyjamas with the nightcap when it wears neither; on the
/// gel in the morning, the sun, and a coffee while it's awake
/// (render/gel/layers.cpp's layerContents); and in the
/// air, confetti at a party or New Year, snow in the winter holidays and
/// hearts on Valentine's.
public struct Dressing: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable { case occasion, night, morning, reading, friday }

    public var kind: Kind
    /// `Boop became a Sprout today`, `It's Friday`.
    public var why: String
    /// What the board wears or shows for it, in a few words: `a party hat
    /// and confetti`. Nil for an occasion it only plays along with.
    public var what: String?
    public var id: String { why }

    public init(kind: Kind, why: String, what: String?) {
        self.kind = kind
        self.why = why
        self.what = what
    }

    /// The reasons on for `when` (the `state`'s tags) and today's
    /// `occasions`, `asleep` when the board's look is, and `gel` for a
    /// board that draws the gel, which alone wears eyewear and pyjamas.
    public static func now(when: [String], occasions: [Occasions.Occasion], asleep: Bool, gel: Bool) -> [Dressing] {
        let on = Set(when)
        let party = ["party", "newyear", "lunar", "programmers"].contains(where: on.contains)
        let hat = on.contains("halloween") ? "halloween" : party ? "party" : on.contains("night") ? "night" : on.contains("winter") ? "winter" : nil
        let glasses = gel && !asleep && on.contains(Occasions.reading)
        let shades = gel && !asleep && !glasses && on.contains("friday") && !on.contains("night") && !on.contains("morning")

        var out: [Dressing] = occasions.map { o in
            var things: [String] = []
            switch o.tag {
            case "halloween"?: if hat == "halloween" { things.append("a witch hat") }
            case "winter"?:
                if hat == "winter" { things.append("a bobble hat") }
                things.append("snow")
            case "valentines"?: things.append("hearts")
            case nil, "newyear"?, "lunar"?, "programmers"?:
                if hat == "party" { things.append("a party hat") }
                if o.tag == nil || o.tag == "newyear" { things.append("confetti") }
            default: break
            }
            return Dressing(kind: .occasion, why: o.why, what: list(things))
        }
        if hat == "night" {
            out.append(Dressing(kind: .night, why: "It's night", what: gel && !glasses && !shades ? "a nightcap and pyjamas" : "a nightcap"))
        }
        if gel && on.contains("morning") && !on.contains("night") {
            out.append(Dressing(kind: .morning, why: "It's morning", what: asleep ? "the sun" : "the sun and a coffee"))
        }
        if glasses { out.append(Dressing(kind: .reading, why: "Your prompt was an essay, or asked for docs", what: "reading glasses")) }
        if shades { out.append(Dressing(kind: .friday, why: "It's Friday", what: "shades")) }
        return out
    }

    /// `a`, `a and b`, `a, b and c`; nil for none.
    static func list(_ things: [String]) -> String? {
        guard let last = things.last else { return nil }
        return things.count == 1 ? last : things.dropLast().joined(separator: ", ") + " and " + last
    }
}
