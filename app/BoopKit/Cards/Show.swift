import Foundation

/// A show (documentation/design/screen-guide.md, "The show"): a result as a
/// picture an agent drew, which Boop holds up full screen. Boop draws the
/// frame and the headline; the agent draws only the picture, a small SVG,
/// held to rules the board can draw and you can read from a chair. This is
/// the check the Mac makes before a show goes anywhere: what's wrong goes
/// back to the agent, which then calls again.
public struct Show: Equatable, Sendable {
    /// The show as its tool's arguments, which `make` reads back.
    var args: [String: Any] {
        var args: [String: Any] = ["headline": headline]
        args["svg"] = svg
        args["image"] = image
        args["link"] = link
        return args
    }

    /// A show from its tool's arguments and what's wrong with it: nil, and
    /// the problems, when it can't show.
    public static func make(_ args: [String: Any]) -> (show: Show?, problems: [String]) {
        let headline = (args["headline"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var problems: [String] = []
        if headline.isEmpty { problems.append("show needs `headline`: the conclusion in a few plain words") }
        if headline.count > headlineMost { problems.append("the headline is \(headline.count) characters: at most \(headlineMost)") }
        let svg = args["svg"] as? String, image = args["image"] as? String
        if let svg {
            problems += Show.problems(svg: svg)
        } else if let image {
            if !image.hasPrefix("/") || !image.lowercased().hasSuffix(".png") || !FileManager.default.fileExists(atPath: image) {
                problems.append("`image` must be an absolute path to a PNG that exists")
            }
        } else {
            problems.append("show needs `svg` or `image`")
        }
        guard problems.isEmpty else { return (nil, problems) }
        return (Show(headline: headline, svg: svg, image: svg == nil ? image : nil,
                     link: (args["link"] as? String).flatMap(Card.openable)), [])
    }
    public var headline: String
    public var svg: String?
    public var image: String?
    public var link: String?

    /// The picture's canvas, in the board's pixels.
    public static let width = 420, height = 190
    /// The most an SVG may be, in bytes; the smallest text and line.
    public static let svgMost = 4096, textLeast = 14.0, lineLeast = 3.0
    /// The most words its text may hold, and the headline's characters.
    public static let wordsMost = 16, headlineMost = 28
    /// The only colours: ink, dim, good, bad, not checked, and the agent's
    /// lane colour as `currentColor`. `none` leaves a shape unfilled.
    public static let colours: Set<String> = ["#e8e6e0", "#9aa0a8", "#5fae5a", "#f08a6c", "#f0b56c", "currentcolor", "none"]
    /// The elements it may hold: shapes, lines and text.
    public static let elements: Set<String> = ["svg", "g", "rect", "circle", "ellipse", "line", "polyline", "polygon",
                                               "path", "text", "tspan", "title"]

    public init(headline: String, svg: String? = nil, image: String? = nil, link: String? = nil) {
        self.headline = headline
        self.svg = svg
        self.image = image
        self.link = link
    }

    /// What's wrong with `svg`, in words an agent can act on; empty when
    /// it's fine.
    public static func problems(svg: String) -> [String] {
        var out: [String] = []
        if svg.utf8.count > svgMost { out.append("the svg is \(svg.utf8.count) bytes: keep it under \(svgMost)") }
        let check = Checker()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = check
        if !parser.parse() { out.append("the svg isn't well-formed XML: \(parser.parserError?.localizedDescription ?? "?")") }
        if check.viewBox != "0 0 \(width) \(height)" {
            out.append("give the svg viewBox=\"0 0 \(width) \(height)\"" + (check.viewBox.map { ", not \"\($0)\"" } ?? ""))
        }
        if !check.banned.isEmpty { out.append("only shapes, lines and text: no \(check.banned.sorted().joined(separator: ", "))") }
        if !check.colours.isEmpty {
            out.append("only the five colours and currentColor: not \(check.colours.sorted().joined(separator: ", "))")
        }
        if let small = check.smallText { out.append("text at least \(Int(textLeast)) px: one is \(small)") }
        if let thin = check.thinLine { out.append("lines at least \(Int(lineLeast)) px: one is \(thin)") }
        if check.words > wordsMost { out.append("at most \(wordsMost) words: it has \(check.words)") }
        if check.links { out.append("no links or outside references") }
        if let wide = check.tooWide {
            out.append("the text \"\(wide)\" runs off the picture (\(width) px wide; a character is about 0.6 of its font-size): shorten it, move it or make it smaller")
        }
        return out
    }

    /// Reads the SVG's elements and attributes as it goes.
    final class Checker: NSObject, XMLParserDelegate {
        var viewBox: String?
        var banned: Set<String> = []
        var colours: Set<String> = []
        var smallText: String?
        var thinLine: String?
        var words = 0
        var links = false
        /// The first text that runs off the picture's sides, at the board's
        /// mono face: about 0.6 of its font-size a character.
        var tooWide: String?
        private var inText = false
        private var text = "", x = 0.0, size = 16.0, anchor = "start"

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let tag = name.split(separator: ":").last.map(String.init)?.lowercased() ?? name
            if !Show.elements.contains(tag) { banned.insert(tag) }
            if tag == "svg" { viewBox = attributes["viewBox"]?.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if tag == "text" {
                inText = true
                text = ""
                x = Double(attributes["x"] ?? "0") ?? 0
                size = Double((attributes["font-size"] ?? "16").replacingOccurrences(of: "px", with: "")) ?? 16
                anchor = attributes["text-anchor"] ?? "start"
            }
            if tag == "tspan" { inText = true }
            for (key, value) in attributes {
                let k = key.lowercased(), v = value.trimmingCharacters(in: .whitespaces).lowercased()
                if k == "href" || k.hasSuffix(":href") || v.contains("url(") { links = true }
                if k.hasPrefix("on") || k == "style" { banned.insert("\(k) attributes") }
                if ["fill", "stroke", "color", "stop-color"].contains(k), !Show.colours.contains(v) { colours.insert(value) }
                if k == "font-size", let size = Double(v.replacingOccurrences(of: "px", with: "")), size < Show.textLeast {
                    smallText = value
                }
                if k == "stroke-width", let w = Double(v.replacingOccurrences(of: "px", with: "")), w < Show.lineLeast {
                    thinLine = value
                }
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let tag = name.split(separator: ":").last.map(String.init)?.lowercased() ?? name
            if tag == "text" {
                inText = false
                let w = Double(text.count) * size * 0.6
                let (left, right) = anchor == "middle" ? (x - w / 2, x + w / 2) : anchor == "end" ? (x - w, x) : (x, x + w)
                if tooWide == nil, left < -1 || right > Double(Show.width) + 1 {
                    tooWide = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText {
                words += string.split(whereSeparator: \.isWhitespace).count
                text += string
            }
        }
    }
}
