import Foundation
import Testing
@testable import LinkKit

@Suite struct WireTests {
    /// Every string as Foundation's `JSONSerialization` writes it with
    /// `.withoutEscapingSlashes`, as an app writing its lines today does.
    func foundation(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// SPEC.md §2: every string is escaped, exactly as Foundation escapes
    /// it, so an app's line keeps its bytes when it moves to the kit:
    /// every ASCII character, control characters, UTF-8 and the line
    /// separators.
    @Test func testStringsAreEscapedAsFoundationEscapesThem() {
        for v in 0..<0x80 {
            let text = "a" + String(Character(Unicode.Scalar(v)!)) + "b"
            #expect(JSON.quote(text) == foundation(text), "U+\(String(v, radix: 16))")
        }
        for text in ["é", "e\u{301}", "💥", "\u{2028}\u{2029}", "\u{FFFD}", "/path/to", #"say "hi" \o/"#, ""] {
            #expect(JSON.quote(text) == foundation(text), "\(text)")
        }
        #expect(JSON.quote("a\"b\\c\nd\u{1}") == #""a\"b\\c\nd\u0001""#)
    }

    /// SPEC.md §2: what the kit writes, any JSON reader reads back as it
    /// was, and so does the kit's own reader.
    @Test func testWhatTheKitWritesReadsBack() throws {
        let text = "quote \" backslash \\ newline \n tab \t nul \u{0} bell \u{7} é 💥 \u{2028}"
        let args: JSONObject = ["text": .string(text), "n": -12, "x": 1.5, "ok": true, "none": .null,
                                "list": [1, "two", ["three": 3]]]
        let line = Wire.do(id: 7, name: "say \"it\"", play: .now, ttl: 5000, args: args)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(object["name"] as? String == "say \"it\"")
        #expect((object["args"] as? [String: Any])?["text"] as? String == text)
        #expect(JSON.parse(line)?.object?["args"] == .object(args))
    }

    /// SPEC.md §3: `state` is the app's fields after `t`, in the app's
    /// order, with no spaces, so a line keeps its bytes; a `t` among them
    /// is the message's, not the app's.
    @Test func testAStateLineIsTheAppsFieldsInOrder() {
        let fields: JSONObject = ["base": "working", "mood": "calm",
                                  "attn": ["agent": "claude", "project": "a\"b", "more": 0], "busy": 1, "vol": 6]
        #expect(Wire.state(fields) == #"{"t":"state","base":"working","mood":"calm","attn":{"agent":"claude","project":"a\"b","more":0},"busy":1,"vol":6}"#)
        #expect(Wire.state([:]) == #"{"t":"state"}"#)
        #expect(Wire.state(["t": "moment", "base": "idle"]) == #"{"t":"state","base":"idle"}"#)
    }

    /// SPEC.md §3: a `do`'s fields in the spec's order; `ttl` only with
    /// `next`, `args` only when there are some.
    @Test func testADoLineMatchesTheSpec() {
        #expect(Wire.do(id: 44, name: "task_complete", play: .next, ttl: 5000, args: ["outcome": "success"])
            == #"{"t":"do","id":44,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}"#)
        #expect(Wire.do(id: 45, name: "wake_up", play: .ifFree, ttl: 5000, args: ["variant": 3, "mood": "curious"])
            == #"{"t":"do","id":45,"name":"wake_up","play":"if_free","args":{"variant":3,"mood":"curious"}}"#)
        #expect(Wire.do(id: 2147483647, name: "listening", play: .now, ttl: 5000, args: [:])
            == #"{"t":"do","id":2147483647,"name":"listening","play":"now"}"#)
    }

    /// SPEC.md §3: `hello`'s five kit fields, and every other field the
    /// app's, in the line's order.
    @Test func testReadsAHello() {
        let line = #"{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.4.0","does":["react","task_complete","listening"],"voice":"1aace295d219","x":{"y":1}}"#
        #expect(Wire.decode(line) == .hello(Hello(kit: 1, app: "boop", id: "b00p-54fe", fw: "1.4.0",
                                                  does: ["react", "task_complete", "listening"],
                                                  fields: ["voice": "1aace295d219", "x": ["y": 1]])))
        guard case .hello(let h) = Wire.decode(line) else { Issue.record("not a hello"); return }
        #expect(h.fields.keys == ["voice", "x"])
        #expect(h.fields["voice"]?.string == "1aace295d219")
        // A name that isn't a string is left out; a missing kit is nil.
        #expect(Wire.decode(#"{"t":"hello","app":"a","id":"i","fw":"f","does":["x",3,null,"y"]}"#)
            == .hello(Hello(kit: nil, app: "a", id: "i", fw: "f", does: ["x", "y"])))
    }

    /// SPEC.md §3: an `ev` with its kind, what the device did and the app's
    /// data; `ended` is the kit's, with its id, `how` and `why`.
    @Test func testReadsEventsAndEnded() {
        #expect(Wire.decode(#"{"t":"ev","kind":"tap","did":"poked"}"#) == .event(DeviceEvent(kind: "tap", did: "poked")))
        #expect(Wire.decode(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":44}}"#)
            == .event(DeviceEvent(kind: "tap", did: "dip", data: ["on": 44])))
        #expect(Wire.decode(#"{"t":"ev","kind":"talk_off"}"#) == .event(DeviceEvent(kind: "talk_off")))
        #expect(Wire.decode(#"{"t":"ev","kind":"ended","data":{"id":44,"how":"cut","why":"tap"}}"#)
            == .ended(Ended(id: 44, how: .cut, why: "tap")))
        #expect(Wire.decode(#"{"t":"ev","kind":"ended","data":{"id":5,"how":"done"}}"#) == .ended(Ended(id: 5, how: .done)))
        #expect(Wire.decode(#"{"t":"ev","kind":"ended","data":{"id":9,"how":"skipped","why":"late"}}"#)
            == .ended(Ended(id: 9, how: .skipped, why: "late")))
        // An `ended` that can't be matched to a `do` isn't an app's event either.
        for odd in [#"{"t":"ev","kind":"ended","data":{"id":5,"how":"later"}}"#,
                    #"{"t":"ev","kind":"ended","data":{"how":"done"}}"#,
                    #"{"t":"ev","kind":"ended"}"#,
                    #"{"t":"ev","did":"poked"}"#] {
            #expect(Wire.decode(odd) == .other(odd))
        }
    }

    /// SPEC.md §2: a number that must be an integer in a range and isn't
    /// one reads as missing: a fraction, a string, a bool, 0, or past
    /// 2147483647.
    @Test func testAnIdThatIsntAnIntegerInRangeIsMissing() {
        for id in ["44.5", "44.0", "4.4e1", "\"44\"", "true", "0", "-3", "2147483648", "null"] {
            let line = #"{"t":"ev","kind":"ended","data":{"id":\#(id),"how":"done"}}"#
            #expect(Wire.decode(line) == .other(line), "id \(id)")
        }
        #expect(Wire.decode(#"{"t":"ev","kind":"ended","data":{"id":2147483647,"how":"done"}}"#)
            == .ended(Ended(id: 2147483647, how: .done)))
        #expect(Wire.decode(#"{"t":"hello","kit":1.0,"app":"a","id":"i","fw":"f","does":[]}"#)
            == .hello(Hello(kit: nil, app: "a", id: "i", fw: "f", does: [])))
    }

    /// SPEC.md §2: types and fields a receiver doesn't know are ignored,
    /// and so is what isn't a message at all. An app's older firmware that
    /// says something of its own where a `hello` would be is the app's to
    /// spot (SPEC.md §6): to the kit it's another line.
    @Test func testUnknownTypesAndNoiseAreOther() {
        for line in [#"{"t":"dbg.ping","up":5}"#, #"{"t":"later","x":1}"#, #"{"kind":"tap"}"#, "rst:0x1 (POWERON_RESET)",
                     #"{"t":"ev","kind":"tap""#, " ", #"{"t":"ev","kind":"tap"} trailing"#,
                     #"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1"}"#] {
            #expect(Wire.decode(line) == .other(line), "\(line)")
        }
        #expect(Wire.decode(#"{"t":"ev","kind":"tap","new":{"deep":[1,2]},"did":"poked"}"#)
            == .event(DeviceEvent(kind: "tap", did: "poked")))
        #expect(Wire.hello == #"{"t":"hello"}"#, "the host's ask")
    }

    /// The kit's reader is strict JSON: escapes and surrogate pairs read
    /// right, raw control characters, bad numbers and trailing commas
    /// don't read, and nesting has a limit.
    @Test func testTheReaderIsStrictJSON() {
        #expect(JSON.parse(#""aé💥\/\n""#) == .string("aé💥/\n"))
        #expect(JSON.parse(#""\ud83d""#) == .string("\u{FFFD}"), "a lone surrogate")
        #expect(JSON.parse(#" { "a" : [ 1 , -0.5e2 , 1E3 ] } "#) == .object(["a": [1, -50.0, 1000.0]]))
        #expect(JSON.parse("9223372036854775808") == .double(9223372036854775808))
        #expect(JSON.parse(#"{"a":1,"b":2,"a":3}"#)?.object?.keys == ["a", "b"])
        #expect(JSON.parse(#"{"a":1,"b":2,"a":3}"#)?.object?["a"] == 3)
        for bad in ["\"a\u{1}b\"", "01", "1.", ".5", "-", "1e", "[1,]", #"{"a":1,}"#, "tru", "[1 2]", #"{"a" 1}"#, #""\x""#,
                    #""\u12G4""#, "\"open", "{", "", String(repeating: "[", count: 40) + String(repeating: "]", count: 40)] {
            #expect(JSON.parse(bad) == nil, "\(bad)")
        }
        #expect(JSON.parse(String(repeating: "[", count: 30) + String(repeating: "]", count: 30)) != nil)
    }

    /// Keys keep the order they were set in; setting one again replaces
    /// it in place, and nil removes it.
    @Test func testAnObjectKeepsItsOrder() {
        var o: JSONObject = ["b": 1, "a": 2]
        o["c"] = "x"
        o["b"] = 5
        #expect(o.json == #"{"b":5,"a":2,"c":"x"}"#)
        o["a"] = nil
        #expect(o.json == #"{"b":5,"c":"x"}"#)
        #expect(o != ["c": "x", "b": 5], "order counts")
        #expect(JSON.double(.infinity).json == "null")
        #expect(JSON.int(3).double == 3)
        #expect(JSON.double(3).int == nil)
    }
}
