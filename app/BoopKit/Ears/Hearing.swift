import Foundation

/// What Boop can hear, like a dog: its name, about twenty words, and three
/// kinds of sound. The only code that decides what the Mac's ears heard:
/// the app's listener (`Ears`, in the app) hands it what the on-device
/// recogniser wrote and what `SoundDetector` measured, and it says which
/// one thing Boop heard, if any, which becomes one `heard` event
/// (`Pipeline.heard`). Nothing it's handed is kept: no audio reaches it,
/// and of the words only which one matched leaves it.
public struct Hearing: Sendable {
    /// One thing heard: a word's or a sound's name, and whether Boop
    /// misheard it.
    public struct Heard: Equatable, Sendable {
        public var what: String
        public var misheard = false

        public init(what: String, misheard: Bool = false) {
            self.what = what
            self.misheard = misheard
        }
    }

    /// Each word Boop knows and the phrases that say it, the first as the
    /// line quotes it. Its name, `name`, is whatever the person called it.
    public static let words: [(what: String, phrases: [String])] = [
        ("good", ["good boy", "good girl", "good job", "good dog"]),
        ("no", ["no", "bad"]),
        ("dance", ["dance"]),
        ("sleep", ["sleep", "nap", "go to sleep"]),
        ("wake", ["wake up"]),
        ("hello", ["hello", "hi"]),
        ("bye", ["bye", "goodbye", "good night"]),
        ("shh", ["shh", "quiet", "hush"]),
        ("stop", ["stop"]),
        ("who", ["who needs me"]),
        ("come", ["come here"]),
        ("sit", ["sit"]),
        ("speak", ["speak"]),
        ("treat", ["treat"]),
        ("fetch", ["fetch"]),
    ]
    /// The sounds, from `SoundDetector`.
    public static let sounds = ["bang", "shout", "singsong"]
    /// Heard on their own; every other word counts only within
    /// `nameGateMs` of Boop's name ("Boop, sit"), so talk at the desk or
    /// on a call doesn't set it off.
    public static let ungated: Set<String> = ["good", "who"]
    public static let nameGateMs: Int64 = 3000
    /// At most one thing heard in this long, but a word right after the
    /// name, which the name was for.
    public static let debounceMs: Int64 = 3000
    /// The commands Boop gets wrong on purpose, one time in
    /// `mishearOdds`. Never its name, praise or a no, shh or stop.
    public static let canMishear: Set<String> = ["dance", "sleep", "sit", "come", "speak", "fetch"]
    public static let mishearOdds = 5

    /// Every phrase and the name, for the recogniser's `contextualStrings`.
    public static func phrases(name: String) -> [String] { [name] + words.flatMap(\.phrases) }

    /// The phrase a word's line quotes.
    public static func phrase(_ what: String) -> String { words.first { $0.what == what }?.phrases.first ?? what }

    let name: [Substring]
    var dice: SplitMix64
    /// How many words of this utterance have been matched already.
    var consumed = 0
    var lastNameAt: Int64?
    var last: (what: String, at: Int64)?

    public init(name: String, seed: UInt64 = 0xEA25) {
        self.name = Self.tokens(name)
        dice = SplitMix64(seed: seed)
    }

    /// Lower-case words, punctuation dropped.
    static func tokens(_ text: String) -> [Substring] {
        text.lowercased().split { !$0.isLetter && $0 != "'" }
    }

    /// The recogniser started a new utterance: none of it is matched yet.
    public mutating func newUtterance() { consumed = 0 }

    /// What the recogniser has written so far in this utterance, at
    /// `now`: the one new thing Boop heard in it, if any. The name gates
    /// the words after it ("Boop, sit" is a sit), and is heard on its own
    /// only when no word follows it.
    public mutating func words(_ text: String, at now: Int64) -> Heard? {
        let tokens = Self.tokens(text)
        var i = consumed
        var named = false
        while i < tokens.count {
            guard let (what, length) = match(tokens, at: i) else {
                i += 1
                continue
            }
            i += length
            consumed = i
            if what == "name" {
                lastNameAt = now
                named = true
                continue
            }
            if !Self.ungated.contains(what), lastNameAt.map({ now - $0 <= Self.nameGateMs }) != true { continue }
            if let heard = emit(what, at: now) { return heard }
        }
        return named ? emit("name", at: now) : nil
    }

    /// A sound `SoundDetector` heard.
    public mutating func sound(_ kind: String, at now: Int64) -> Heard? {
        Self.sounds.contains(kind) ? emit(kind, at: now) : nil
    }

    /// The longest phrase, or the name, that starts at `i`.
    func match(_ tokens: [Substring], at i: Int) -> (String, Int)? {
        var best: (String, Int)?
        func fits(_ phrase: [Substring]) -> Bool {
            !phrase.isEmpty && i + phrase.count <= tokens.count && Array(tokens[i..<(i + phrase.count)]) == phrase
        }
        if fits(name) { best = ("name", name.count) }
        for (what, phrases) in Self.words {
            for p in phrases.map(Self.tokens) where fits(p) && p.count > (best?.1 ?? 0) { best = (what, p.count) }
        }
        return best
    }

    /// `what` as heard now, unless something was just heard (a word right
    /// after the name excepted), with the die cast for a command.
    mutating func emit(_ what: String, at now: Int64) -> Heard? {
        if let last, now - last.at < Self.debounceMs, !(last.what == "name" && what != "name") { return nil }
        last = (what, now)
        let misheard = Self.canMishear.contains(what) && dice.int(in: 1...Self.mishearOdds) == 1
        return Heard(what: what, misheard: misheard)
    }
}

/// The Mac's mic as Boop's ears measure it, a buffer at a time: its level
/// and the voice's pitch, never the sound itself. It hears a bang (loud and
/// short), a shout (loud and held) and singing (a voice whose pitch swings
/// wide). The numbers are first guesses, to tune by ear.
public struct SoundDetector: Sendable {
    /// A bang peaks over `bangDb` and is over in `bangMaxMs`; a shout
    /// stays over `shoutDb` for `shoutMinMs`.
    public static let bangDb: Float = -18, shoutDb: Float = -22
    public static let bangMaxMs: Int64 = 300, shoutMinMs: Int64 = 500
    /// Singing: a voice over `voicedDb` whose pitch spans `singSemitones`
    /// within `singWindowMs`, over at least `singMinFrames` voiced buffers.
    public static let voicedDb: Float = -45, singSemitones: Float = 9
    public static let singWindowMs: Int64 = 2000, singMinFrames = 12

    var loudSince: Int64?
    var loudPeak: Float = -.infinity
    var shouted = false
    var pitches: [(at: Int64, semitone: Float)] = []

    public init() {}

    /// One buffer's level in dBFS and, when it's voiced, its pitch in Hz:
    /// the sound it completes, if any.
    public mutating func feed(levelDb: Float, pitchHz: Float?, at now: Int64) -> String? {
        if levelDb >= Self.shoutDb {
            if loudSince == nil {
                loudSince = now
                loudPeak = levelDb
                shouted = false
            }
            loudPeak = max(loudPeak, levelDb)
            if !shouted, let since = loudSince, now - since >= Self.shoutMinMs {
                shouted = true
                return "shout"
            }
        } else if let since = loudSince {
            loudSince = nil
            if !shouted, now - since < Self.bangMaxMs, loudPeak >= Self.bangDb { return "bang" }
        }
        guard let hz = pitchHz, hz > 60, hz < 1100, levelDb >= Self.voicedDb else { return nil }
        pitches.append((now, 12 * log2(hz / 440)))
        pitches.removeAll { now - $0.at > Self.singWindowMs }
        guard pitches.count >= Self.singMinFrames, let lo = pitches.map(\.semitone).min(), let hi = pitches.map(\.semitone).max(),
              hi - lo >= Self.singSemitones else { return nil }
        pitches = []
        return "singsong"
    }
}
