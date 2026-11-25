import Foundation
import XCTest

/// The boards' own times, read from the firmware's tables, for a test that
/// pins a time of the Mac's against what a board really plays: how long a
/// design's loop runs, when its sound starts, how long a bubble stays up.
enum FirmwareTables {
    /// The repository's root.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL

    /// The largest number the first group of `pattern` matches in `file`:
    /// in its table that starts at `start` and ends at the next `};`, or
    /// anywhere in it with no `start`. A fraction counts up.
    static func longest(_ file: String, _ start: String?, _ pattern: String) throws -> Int64 {
        let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        var table = text
        if let start {
            let from = try XCTUnwrap(text.range(of: start), "\(file) has no \(start)").upperBound
            table = String(text[from..<(try XCTUnwrap(text.range(of: "};", range: from..<text.endIndex))).lowerBound])
        }
        let re = try NSRegularExpression(pattern: pattern)
        return re.matches(in: table, range: NSRange(table.startIndex..., in: table))
            .compactMap { Double(table[Range($0.range(at: 1), in: table)!]).map { Int64($0.rounded(.up)) } }.max() ?? 0
    }

    /// Pixel's longest design loop, of every mood and state.
    static func pixelLongestLoopMs() throws -> Int64 {
        try longest("characters/pixel/firmware/include/faces.h", "static const Scene kScenes[",
                    #"\{\d+, \d+, (\d+), -?\d+, -?\d+, \d+, \d+, \d+\}"#)
    }

    /// When Pixel's latest sound starts in a loop.
    static func pixelLatestVoiceMs() throws -> Int64 {
        try longest("characters/pixel/firmware/include/sfx.h", "static const Score kScore[] = {", #"\{k\w+, \d+, \w+, \d+, \d+, (\d+)\},"#)
    }

    /// The gel's longest loop: every recipe of the slime (each mood's
    /// takes, the gestures', the pastimes') and of its big finishes. A take
    /// starts inside a loop, at its reveal.
    static func gelLongestLoopMs() throws -> Int64 {
        max(try longest("characters/boop/firmware/include/slime.h", nil, #"\{T::literal\(([\d.]+)\),F::fromRaw"#),
            try longest("characters/boop/firmware/src/render/gel/finish.cpp", "kFinishRecipes[", #"\{AT\((\d+)\),"#))
    }

    /// How long the bubble stays up after a take (firmware `Behaviour::kBubbleReadMs`).
    static func bubbleReadMs() throws -> Int64 {
        let behaviour = try String(contentsOf: root.appendingPathComponent("firmware/src/app/behaviour.h"), encoding: .utf8)
        return try XCTUnwrap(behaviour.firstMatch(of: /kBubbleReadMs = (\d+);/).flatMap { Int64($0.1) })
    }
}
