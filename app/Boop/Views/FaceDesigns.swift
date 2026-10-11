import BoopKit
import CoreGraphics
import Foundation

/// Each look's face as its first variation starts, open-eyed and
/// blinking, for the popover's tile: the device's own shapes, without
/// the props. They're the face's `mac/faces.json`
/// (characters/CHARACTER.md §9), which facegen writes into the Pixel
/// pack.
enum FaceDesigns {
    /// Where the faces sit in the designs' 320×240 screen.
    static var box: CGRect { table.box }

    /// The faces' colours, as 0xRRGGBB, by the colour byte of a rectangle.
    static var colors: [UInt32] { table.colors }

    /// By "mood/look": base64 of five bytes a rectangle, x and y from the
    /// box's corner, width, height and colour (into `colors`).
    static var faces: [String: (open: String, shut: String)] { table.faces }

    private struct Table {
        var box = CGRect.zero
        var colors: [UInt32] = []
        var faces: [String: (open: String, shut: String)] = [:]
    }

    /// The face's designs, read the first time they're used; none for a
    /// pack with no pixel face.
    nonisolated(unsafe) private static let table: Table = {
        guard let file = CharacterPack.active.file("mac/faces.json"),
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Table() }
        var t = Table()
        if let b = json["box"] as? [Int], b.count == 4 { t.box = CGRect(x: b[0], y: b[1], width: b[2], height: b[3]) }
        t.colors = (json["colors"] as? [NSNumber] ?? []).map(\.uint32Value)
        for (key, face) in json["faces"] as? [String: [String: String]] ?? [:] {
            t.faces[key] = (open: face["open"] ?? "", shut: face["shut"] ?? "")
        }
        return t
    }()
}
