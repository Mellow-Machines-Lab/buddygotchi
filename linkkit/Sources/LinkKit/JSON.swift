import Foundation

/// A JSON value, as the app's parts of a message carry it: `state`'s
/// fields, a `do`'s `args`, an `ev`'s `data` and `hello`'s own fields
/// (SPEC.md §2). Objects keep their keys in order, so a line the app builds
/// comes out byte for byte the same every time.
///
/// Literals build one: `["say": ["take": "word.success.done__calm"], "loops": 1]`.
public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object(JSONObject)

    /// The value as one line of JSON, with no spaces.
    public var json: String {
        var out = ""
        write(to: &out)
        return out
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Only an integer: `44`, not `44.0`, `"44"` or `true` (SPEC.md §2).
    public var int: Int? {
        if case .int(let n) = self { return n }
        return nil
    }

    /// Any number.
    public var double: Double? {
        switch self {
        case .int(let n): Double(n)
        case .double(let d): d
        default: nil
        }
    }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var array: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var object: JSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        // JSON has no infinity or NaN.
        case .double(let d): out += d.isFinite ? String(d) : "null"
        case .string(let s): JSON.quote(s, to: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let object): object.write(to: &out)
        }
    }

    /// `text` as a JSON string, quotes included. Escapes exactly what
    /// Foundation's `JSONSerialization` does with `.withoutEscapingSlashes`
    /// (`"`, `\` and control characters, the common ones in short form),
    /// so a line built here matches one built there byte for byte;
    /// everything else, UTF-8 included, is left as it is.
    public static func quote(_ text: String) -> String {
        var out = ""
        quote(text, to: &out)
        return out
    }

    static func quote(_ text: String, to out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            case 0..<0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

/// A JSON object whose keys keep the order they were added in. Setting a
/// key that's there already replaces its value in place.
public struct JSONObject: Equatable, Sendable, CustomStringConvertible {
    public private(set) var fields: [(key: String, value: JSON)] = []

    public init() {}

    public init(_ fields: [(String, JSON)]) {
        for (key, value) in fields { self[key] = value }
    }

    public var isEmpty: Bool { fields.isEmpty }
    public var keys: [String] { fields.map(\.key) }

    /// A key's value; setting nil removes it.
    public subscript(key: String) -> JSON? {
        get { fields.first { $0.key == key }?.value }
        set {
            let i = fields.firstIndex { $0.key == key }
            switch (i, newValue) {
            case (let i?, let value?): fields[i].value = value
            case (let i?, nil): fields.remove(at: i)
            case (nil, let value?): fields.append((key, value))
            case (nil, nil): break
            }
        }
    }

    /// The object as one line of JSON: `{"a":1,"b":"x"}`.
    public var json: String {
        var out = ""
        write(to: &out)
        return out
    }

    public var description: String { json }

    func write(to out: inout String) {
        out += "{"
        writeFields(to: &out, first: true)
        out += "}"
    }

    /// `"key":value` for each field, each after a comma unless `first`
    /// and it's the first: a message's fields go after its own.
    func writeFields(to out: inout String, first: Bool) {
        for (i, field) in fields.enumerated() {
            if i > 0 || !first { out += "," }
            JSON.quote(field.key, to: &out)
            out += ":"
            field.value.write(to: &out)
        }
    }

    public static func == (a: JSONObject, b: JSONObject) -> Bool {
        a.fields.count == b.fields.count && zip(a.fields, b.fields).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self.init(elements)
    }
}

extension JSON: ExpressibleByStringInterpolation, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) { self = .object(JSONObject(elements)) }
}

// MARK: - Reading

extension JSON {
    /// Nesting deeper than this doesn't parse, so a hostile line can't
    /// overflow the stack.
    static let maxDepth = 32

    /// Parses one JSON value that fills `text` (whitespace aside), or nil
    /// if it isn't one. Strict: no raw control characters in strings, no
    /// trailing commas. A number with no fraction or exponent that fits an
    /// `Int` is `.int`; any other is `.double`. Objects keep the line's key
    /// order, and a repeated key keeps its last value. For the app to read
    /// a line the kit doesn't know (`Wire.Message.other`).
    public static func parse(_ text: String) -> JSON? {
        var parser = Parser(bytes: Array(text.utf8))
        guard let value = parser.value(depth: 0) else { return nil }
        parser.skipSpace()
        return parser.i == parser.bytes.count ? value : nil
    }

    struct Parser {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        var peek: UInt8? { i < bytes.count ? bytes[i] : nil }

        mutating func skipSpace() {
            while let b = peek, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1 }
        }

        mutating func eat(_ byte: UInt8) -> Bool {
            guard peek == byte else { return false }
            i += 1
            return true
        }

        mutating func literal(_ word: String, _ value: JSON) -> JSON? {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { return nil }
            i += w.count
            return value
        }

        mutating func value(depth: Int) -> JSON? {
            guard depth <= JSON.maxDepth else { return nil }
            skipSpace()
            switch peek {
            case UInt8(ascii: "{"): return object(depth: depth)
            case UInt8(ascii: "["): return array(depth: depth)
            case UInt8(ascii: "\""): return string().map(JSON.string)
            case UInt8(ascii: "t"): return literal("true", .bool(true))
            case UInt8(ascii: "f"): return literal("false", .bool(false))
            case UInt8(ascii: "n"): return literal("null", .null)
            case let b? where b == UInt8(ascii: "-") || (0x30...0x39).contains(b): return number()
            default: return nil
            }
        }

        mutating func object(depth: Int) -> JSON? {
            i += 1
            var object = JSONObject()
            skipSpace()
            if eat(UInt8(ascii: "}")) { return .object(object) }
            while true {
                skipSpace()
                guard peek == UInt8(ascii: "\""), let key = string() else { return nil }
                skipSpace()
                guard eat(UInt8(ascii: ":")), let value = value(depth: depth + 1) else { return nil }
                object[key] = value
                skipSpace()
                if eat(UInt8(ascii: ",")) { continue }
                return eat(UInt8(ascii: "}")) ? .object(object) : nil
            }
        }

        mutating func array(depth: Int) -> JSON? {
            i += 1
            var items: [JSON] = []
            skipSpace()
            if eat(UInt8(ascii: "]")) { return .array(items) }
            while true {
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
                skipSpace()
                if eat(UInt8(ascii: ",")) { continue }
                return eat(UInt8(ascii: "]")) ? .array(items) : nil
            }
        }

        mutating func string() -> String? {
            i += 1
            var out: [UInt8] = []
            while let b = peek {
                i += 1
                switch b {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard let e = peek else { return nil }
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        guard let scalar = unicodeEscape() else { return nil }
                        out += Array(String(Character(scalar)).utf8)
                    default: return nil
                    }
                case 0..<0x20:
                    return nil
                default:
                    out.append(b)
                }
            }
            return nil
        }

        /// The four hex digits after `\u`, and a low surrogate's after
        /// that when they start a pair. A surrogate on its own reads as
        /// U+FFFD.
        mutating func unicodeEscape() -> Unicode.Scalar? {
            guard let high = hex4() else { return nil }
            if (0xD800..<0xDC00).contains(high) {
                let save = i
                if eat(UInt8(ascii: "\\")), eat(UInt8(ascii: "u")), let low = hex4(), (0xDC00..<0xE000).contains(low) {
                    return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
                }
                i = save
                return "\u{FFFD}"
            }
            return Unicode.Scalar(high) ?? "\u{FFFD}"
        }

        mutating func hex4() -> UInt32? {
            guard i + 4 <= bytes.count else { return nil }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[i]
                i += 1
                switch b {
                case 0x30...0x39: v = v << 4 | UInt32(b - 0x30)
                case 0x41...0x46: v = v << 4 | UInt32(b - 0x41 + 10)
                case 0x61...0x66: v = v << 4 | UInt32(b - 0x61 + 10)
                default: return nil
                }
            }
            return v
        }

        mutating func number() -> JSON? {
            let start = i
            _ = eat(UInt8(ascii: "-"))
            func digits() -> Int {
                let from = i
                while let b = peek, (0x30...0x39).contains(b) { i += 1 }
                return i - from
            }
            if eat(UInt8(ascii: "0")) {
                // No leading zeros.
            } else if digits() == 0 {
                return nil
            }
            var integer = true
            if eat(UInt8(ascii: ".")) {
                integer = false
                guard digits() > 0 else { return nil }
            }
            if eat(UInt8(ascii: "e")) || eat(UInt8(ascii: "E")) {
                integer = false
                _ = eat(UInt8(ascii: "+")) || eat(UInt8(ascii: "-"))
                guard digits() > 0 else { return nil }
            }
            let text = String(decoding: bytes[start..<i], as: UTF8.self)
            if integer, let n = Int(text) { return .int(n) }
            return Double(text).map(JSON.double)
        }
    }
}
