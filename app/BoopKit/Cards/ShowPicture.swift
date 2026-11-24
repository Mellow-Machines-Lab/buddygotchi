#if canImport(AppKit)
import AppKit
#endif
import Foundation

/// A show's picture as the board draws it (firmware/src/render/show.h): the
/// agent's SVG or PNG drawn at the board's own pixels, `Show.width` by
/// `Show.height`, each pixel one of 16 colours, run-length coded so a mostly
/// empty picture is small on the link. It goes to the board as a blob
/// (linkkit/SPEC.md §3), and the `state`'s `show` names it.
public enum ShowPicture {
    /// The colours by index, as the board's `kShowInk`: 0 none (the card
    /// shows through), the show's rule colours (ink, dim, good, bad, not
    /// checked), 6 the agent's lane colour (`currentColor`), then greys
    /// for a picture made from a PNG.
    public static let palette: [(r: Int, g: Int, b: Int)] = [
        (0, 0, 0), (0xe8, 0xe6, 0xe0), (0x9a, 0xa0, 0xa8), (0x5f, 0xae, 0x5a), (0xf0, 0x8a, 0x6c), (0xf0, 0xb5, 0x6c),
        (0xff, 0x00, 0xff), (0x20, 0x20, 0x20), (0x38, 0x38, 0x38), (0x50, 0x50, 0x50), (0x68, 0x68, 0x68),
        (0x80, 0x80, 0x80), (0xb0, 0xb0, 0xb0), (0xc8, 0xc8, 0xc8), (0xf8, 0xf8, 0xf8), (0x10, 0x10, 0x10),
    ]
    /// The lane's index, and the colour an SVG's `currentColor` is drawn in
    /// to find it, one no rule colour is near.
    public static let lane = 6
    static let laneSentinel = "#ff00ff"
    /// The most a coded picture may be: the board's room for it
    /// (`Device::kShowBytes`). A busier one goes with its headline alone.
    public static let mostBytes = 12 * 1024

    /// The picture's colours, a byte a pixel, row by row; nil when it
    /// can't be drawn here.
    public static func indices(_ show: Show) -> [UInt8]? {
        #if canImport(AppKit)
        let image: NSImage?
        var rules = false
        if let svg = show.svg {
            let drawn = svg.replacingOccurrences(of: "currentColor", with: laneSentinel)
                .replacingOccurrences(of: "<svg ", with: "<svg font-family=\"Menlo, monospace\" ")
            image = NSImage(data: Data(drawn.utf8))
            rules = true
        } else {
            image = show.image.flatMap(NSImage.init(contentsOfFile:))
        }
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let w = Show.width, h = Show.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        // An SVG fills its viewBox, the picture's own size; a PNG keeps its
        // shape, fitted and centred.
        var rect = NSRect(x: 0, y: 0, width: w, height: h)
        if !rules {
            let scale = min(CGFloat(w) / image.size.width, CGFloat(h) / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            rect = NSRect(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2, width: size.width, height: size.height)
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        var out = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let a = Int(data[i * 4 + 3])
            guard a >= 128 else { continue }
            // Premultiplied: back to the colour itself.
            let r = Int(data[i * 4]) * 255 / a, g = Int(data[i * 4 + 1]) * 255 / a, b = Int(data[i * 4 + 2]) * 255 / a
            out[i] = UInt8(nearest(r, g, b, rules: rules))
        }
        return out
        #else
        return nil
        #endif
    }

    /// The nearest colour's index: among the rule colours and the lane's
    /// for an SVG, among all but the lane's for a PNG.
    static func nearest(_ r: Int, _ g: Int, _ b: Int, rules: Bool) -> Int {
        let candidates = rules ? Array(1...6) : Array(1...5) + Array(7..<palette.count)
        return candidates.min { distance(palette[$0], r, g, b) < distance(palette[$1], r, g, b) } ?? 1
    }

    static func distance(_ p: (r: Int, g: Int, b: Int), _ r: Int, _ g: Int, _ b: Int) -> Int {
        let dr = p.r - r, dg = p.g - g, db = p.b - b
        return 2 * dr * dr + 4 * dg * dg + 3 * db * db
    }

    /// The runs of `indices` (render/show.h): a byte each, its colour in
    /// the high four bits and its length less one in the low four (1–15),
    /// or 15 there and the length less 16 in the next byte (16–271).
    public static func encode(_ indices: [UInt8]) -> Data {
        var out = Data()
        var i = 0
        while i < indices.count {
            let colour = indices[i]
            var n = 1
            while i + n < indices.count, indices[i + n] == colour, n < 271 { n += 1 }
            if n <= 15 {
                out.append(colour << 4 | UInt8(n - 1))
            } else {
                out.append(colour << 4 | 15)
                out.append(UInt8(n - 16))
            }
            i += n
        }
        return out
    }

    /// The colours `data` codes, or nil when it doesn't code a whole
    /// picture: for tests, and to check what goes out.
    public static func decode(_ data: Data, count: Int = Show.width * Show.height) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let colour = bytes[i] >> 4, low = Int(bytes[i] & 15)
            i += 1
            var n = low + 1
            if low == 15 {
                guard i < bytes.count else { return nil }
                n = 16 + Int(bytes[i])
                i += 1
            }
            out += [UInt8](repeating: colour, count: n)
        }
        return out.count == count ? out : nil
    }

    /// The coded picture for the board, or nil when it can't be drawn or is
    /// too busy for the board's room.
    public static func bytes(_ show: Show) -> Data? {
        guard let indices = indices(show) else { return nil }
        let coded = encode(indices)
        return coded.count <= mostBytes ? coded : nil
    }
}
