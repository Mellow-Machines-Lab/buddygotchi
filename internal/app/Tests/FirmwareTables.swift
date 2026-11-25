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
    static func longest(_ file: String, _ start: String?, _ pattern: String, without: (String) -> String = { $0 }) throws -> Int64 {
        let text = without(try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8))
        var table = text
        if let start {
            let from = try XCTUnwrap(text.range(of: start), "\(file) has no \(start)").upperBound
            table = String(text[from..<(try XCTUnwrap(text.range(of: "};", range: from..<text.endIndex))).lowerBound])
        }
        let re = try NSRegularExpression(pattern: pattern)
        return re.matches(in: table, range: NSRange(table.startIndex..., in: table))
            .compactMap { Double(table[Range($0.range(at: 1), in: table)!]).map { Int64($0.rounded(.up)) } }.max() ?? 0
    }

    /// The gel's longest loop: every recipe of the slime (each state's
    /// takes, the gestures', the pastimes') and of its big finishes. A take
    /// starts inside a loop, at its reveal. Needs you's row is left out:
    /// its knock climbs for as long as nobody comes, and no Moment rides it.
    static func gelLongestLoopMs() throws -> Int64 {
        max(try longest("characters/boop/firmware/include/slime.h", nil, #"\{T::literal\(([\d.]+)\),F::fromRaw"#,
                        without: { withoutRow(needsYouRow, ofTable: "kRecipes[kRecipeStates]", in: $0) }),
            try longest("characters/boop/firmware/src/render/gel/finish.cpp", "kFinishRecipes[", #"\{AT\((\d+)\),"#))
    }

    /// Needs you's row in the gel's recipes (`SceneState::kNeedsYou`).
    static let needsYouRow = 2

    /// `text` less one row of a table, a line a row after its first line,
    /// up to its `};`.
    static func withoutRow(_ row: Int, ofTable start: String, in text: String) -> String {
        var inTable = false, index = 0
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            if line.contains(start) { inTable = true; return true }
            guard inTable else { return true }
            if line == "};" { inTable = false; return true }
            defer { index += 1 }
            return index != row
        }.joined(separator: "\n")
    }

    /// How long the bubble stays up after a take (firmware `Behaviour::kBubbleReadMs`).
    static func bubbleReadMs() throws -> Int64 {
        let behaviour = try String(contentsOf: root.appendingPathComponent("firmware/src/app/behaviour.h"), encoding: .utf8)
        return try XCTUnwrap(behaviour.firstMatch(of: /kBubbleReadMs = (\d+);/).flatMap { Int64($0.1) })
    }
}
