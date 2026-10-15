import Foundation
import Testing
@testable import LinkKit

/// Records what the link sends, and lets a test play the device.
final class FakeTransport: Transport, @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    var name: String { "fake" }

    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {}
    func send(_ line: String) { lock.withLock { lines.append(line) } }
    func reconnect() {}
    func stop() {}

    var sent: [String] { lock.withLock { lines } }
    func types() -> [String] { sent.map { JSON.parse($0)?.object?["t"]?.string ?? "?" } }
    /// The `do`s sent, as the device reads them.
    var dos: [JSONObject] { sent.compactMap { JSON.parse($0)?.object }.filter { $0["t"] == "do" } }
    func clear() { lock.withLock { lines.removeAll() } }
}

let helloLine = #"{"t":"hello","kit":1,"app":"pip","id":"pip-54fe","fw":"1.0.0","does":["react","cheer","listening"],"voice":"abc"}"#
let fields: JSONObject = ["base": "working", "mood": "calm", "busy": 1, "vol": 6]

/// A link to a fake device, connected and past `hello` unless asked not to.
func makeLink(connected: Bool = true, hello: Bool = true) -> (DeviceLink, FakeTransport, Box<String>) {
    let transport = FakeTransport()
    let logs = Box<String>()
    let link = DeviceLink(app: "pip", transport: transport, log: { logs.add($0) })
    if connected { link.connection(true, now: 0) }
    if hello { link.receive(helloLine, now: 0) }
    transport.clear()
    return (link, transport, logs)
}

func ended(_ id: Int, _ how: String, _ why: String? = nil) -> String {
    #"{"t":"ev","kind":"ended","data":{"id":\#(id),"how":"\#(how)""# + (why.map { #","why":"\#($0)""# } ?? "") + "}}"
}

@Suite struct LinkStateTests {
    /// SPEC.md §5: a `state` on every change, and the latest again once
    /// 10 s have passed without one.
    /// SPEC.md §5: a `hello` with a different `boot` means the device
    /// restarted and forgot what it was asked, so every `do` still waiting
    /// fails at once, while the same `boot` again, or none, changes nothing.
    @Test func testANewBootFailsWhatWaits() {
        func hello(_ boot: String?) -> String {
            #"{"t":"hello","kit":1,"app":"pip","id":"pip-54fe","fw":"1.0.0""#
                + (boot.map { #","boot":"\#($0)""# } ?? "") + #","does":["react"]}"#
        }
        let (link, _, logs) = makeLink(hello: false)
        link.receive(hello("0000ab12"), now: 0)
        #expect(link.hello?.boot == "0000ab12")
        let outcomes = Box<DeviceLink.Outcome>()
        link.do("react", now: 0) { outcomes.add($0) }
        link.receive(hello("0000ab12"), now: 100)  // the 60 s repeat
        link.receive(hello(nil), now: 200)
        #expect(outcomes.all.isEmpty)
        link.receive(hello("77770001"), now: 300)
        #expect(outcomes.all == [.failed(.restarted)])
        #expect(DeviceLink.Failure.restarted.description == "the device restarted")
        #expect(logs.all.contains { $0.contains("the device restarted") })
        #expect(link.lastBoot == "77770001")
    }

    @Test func testStateGoesOutOnChangeAndEveryTenSeconds() {
        let (link, transport, _) = makeLink()
        link.update(state: fields, now: 0)
        link.update(state: fields, now: 1000)  // nothing changed
        #expect(transport.sent.count == 1)
        var busier = fields
        busier["busy"] = 2
        link.update(state: busier, now: 2000)
        #expect(transport.sent.count == 2)
        link.tick(now: 11_999)
        #expect(transport.sent.count == 2)
        link.tick(now: 12_000)
        #expect(transport.sent.count == 3)
        #expect(transport.sent[2] == transport.sent[1], "the keepalive is the latest line again")
        #expect(transport.sent[2] == #"{"t":"state","base":"working","mood":"calm","busy":2,"vol":6}"#)
        #expect(link.state == busier)
        #expect(DeviceLink.keepaliveMs == 10_000)
    }

    /// SPEC.md §5: when a link comes up the host sends its latest `state`
    /// at once, after asking for the device's `hello`, and it answers every
    /// `hello` with the latest `state`, so a device that rebooted catches up.
    @Test func testConnectAndEveryHelloGetTheLatestState() {
        let (link, transport, logs) = makeLink(connected: false, hello: false)
        link.update(state: fields, now: 0)
        link.connection(true, now: 100)
        #expect(transport.types() == ["state", "hello", "state"])
        #expect(logs.all.contains("device link: connected (fake)"))
        link.receive(helloLine, now: 200)
        link.receive(helloLine, now: 60_200)
        #expect(transport.types() == ["state", "hello", "state", "state", "state"])
        #expect(Set(transport.sent) == [Wire.state(fields), Wire.hello])
        #expect(link.hello?.id == "pip-54fe")
        #expect(link.hello?.fields["voice"] == "abc")
        link.tick(now: 70_199)
        #expect(transport.sent.count == 5, "a hello's answer counts as the keepalive")
    }

    /// SPEC.md §2: a host never sends a message longer than 512 bytes. A
    /// `state` that would be is logged once and not sent, and the last one
    /// that fit stays the keepalive.
    @Test func testAStateTooLongIsNeverSent() {
        let (link, transport, logs) = makeLink()
        link.update(state: fields, now: 0)
        var long = fields
        long["note"] = .string(String(repeating: "x", count: Wire.maxLine))
        link.update(state: long, now: 100)
        link.update(state: long, now: 200)
        #expect(transport.sent == [Wire.state(fields)])
        #expect(logs.all.filter { $0.contains("is over 512: not sent") }.count == 1)
        #expect(link.state == fields)
        link.tick(now: 10_000)
        #expect(transport.sent == [Wire.state(fields), Wire.state(fields)], "the last that fit is the keepalive")
    }

    /// Every message goes to `onSend` with who asked for it: the app's name
    /// for a `do`, `app` when it doesn't say, and `link` for the link's
    /// own messages, every `state` and the ask for `hello`.
    @Test func testOnSendTracesEveryMessageWithItsSender() {
        let (link, _, _) = makeLink(connected: false, hello: false)
        let traced = Box<String>()
        link.onSend = { line, by in traced.add("\(by) \(JSON.parse(line)?.object?["t"]?.string ?? "?")") }
        link.update(state: fields, now: 0)
        link.connection(true, now: 0)
        link.receive(helloLine, now: 0)
        link.do("react", by: "brain", now: 0) { _ in }
        link.do("cheer", by: "tool", now: 0) { _ in }
        link.do("cheer", now: 0) { _ in }
        #expect(traced.all == ["link state", "link hello", "link state", "link state", "brain do", "tool do", "app do"])
    }

    /// With no transport the link sends into nothing: `onSend` still
    /// traces the `state`, and a `do` fails at once.
    @Test func testNoTransportIsNeverConnected() {
        let link = DeviceLink(app: "pip", transport: nil)
        let traced = Box<String>()
        link.onSend = { line, _ in traced.add(line) }
        link.update(state: fields, now: 0)
        #expect(traced.all == [Wire.state(fields)])
        var outcome: DeviceLink.Outcome?
        #expect(link.do("react", now: 0) { outcome = $0 } == nil)
        #expect(outcome == .failed(.notConnected))
    }
}

@Suite struct LinkHelloTests {
    /// SPEC.md §3, §5: a device that still counts the host as there (an
    /// app relaunched within 30 s, or one taking over a Bluetooth link macOS
    /// kept open) says no `hello` unasked, so the host asks with a bare
    /// `hello` when the link comes up, before its `state`, and again every
    /// 10 s until one comes; not once one has, nor while the device doesn't
    /// fit. A new link asks again.
    @Test func testTheHostAsksForHelloUntilOneComes() {
        let (link, transport, _) = makeLink(connected: false, hello: false)
        link.update(state: fields, now: 0)
        transport.clear()
        link.connection(true, now: 100)
        #expect(transport.sent == [Wire.hello, Wire.state(fields)])
        link.tick(now: 10_099)
        #expect(transport.sent.count == 2)
        link.tick(now: 10_100)
        #expect(transport.sent == [Wire.hello, Wire.state(fields), Wire.hello, Wire.state(fields)], "asked again")
        link.receive(helloLine, now: 10_200)
        transport.clear()
        link.tick(now: 20_200)
        #expect(transport.sent == [Wire.state(fields)], "not once it has")
        link.connection(false, now: 20_300)
        link.connection(true, now: 20_400)
        #expect(transport.types() == ["state", "hello", "state"], "asked again on a new link")
        link.receive(#"{"t":"hello","kit":2,"app":"pip","id":"i","fw":"9","does":[]}"#, now: 20_500)
        transport.clear()
        link.tick(now: 40_000)
        #expect(transport.types() == ["state"], "nor while it doesn't fit")
    }

    /// SPEC.md §6: a device that doesn't fit still gets `state` (at once,
    /// on change and as the keepalive) but no `do`, and no `hello` ask;
    /// its `ev`s are dropped, and `trouble` says why, logged once.
    @Test func testTroubleGetsStateButNoDo() {
        let (link, transport, logs) = makeLink(hello: false)
        let events = Box<DeviceEvent>()
        link.onEvent = { events.add($0) }
        link.update(state: fields, now: 0)
        transport.clear()
        let old = #"{"t":"hello","app":"pip","id":"pip-7f3a","fw":"0.3.1","does":["react"]}"#
        for t in [100, 200] as [Int64] { link.receive(old, now: t) }
        #expect(link.trouble == .tooOld)
        #expect(link.trouble?.description == "the device's firmware is too old for this app: flash it")
        #expect(logs.all.filter { $0.contains("too old") }.count == 1)
        #expect(transport.sent == [Wire.state(fields), Wire.state(fields)], "each gets the latest state")
        var busier = fields
        busier["busy"] = 3
        link.update(state: busier, now: 300)
        link.tick(now: 10_299)
        #expect(transport.sent.count == 3, "a change goes out")
        link.tick(now: 10_300)
        #expect(transport.sent.count == 4, "and the keepalive")
        link.receive(#"{"t":"ev","kind":"tap"}"#, now: 10_400)
        #expect(events.all.isEmpty, "its events are dropped")
        var outcome: DeviceLink.Outcome?
        #expect(link.do("react", now: 60_000) { outcome = $0 } == nil)
        #expect(outcome == .failed(.incompatible))
        #expect(transport.types().allSatisfy { $0 == "state" }, "no do, and no hello ask")
        #expect(link.hello == nil)

        // Flashed over a link that stayed up: the new firmware hears the
        // keepalive, and a hello that fits clears the trouble and gets the
        // latest state.
        transport.clear()
        link.receive(helloLine, now: 61_000)
        #expect(link.trouble == nil)
        #expect(transport.sent == [Wire.state(busier)])
        #expect(link.do("react", now: 61_000) { _ in } != nil)
    }

    /// SPEC.md §6: a `kit` this host doesn't know means the firmware is
    /// too new; none at all, too old. SPEC.md §3: a host drives only the
    /// `app` it was written for. Either way the device still gets `state`,
    /// but no `do`, and its `ev`s are dropped; the log says who it is.
    @Test func testAHelloThatDoesntFitIsTrouble() {
        let cases: [(String, DeviceLink.Trouble, String)] = [
            (#"{"t":"hello","kit":2,"app":"pip","id":"i","fw":"9","does":["react"]}"#, .tooNew,
             "the device's firmware is too new for this app: update the app"),
            (#"{"t":"hello","app":"pip","id":"i","fw":"0","does":["react"]}"#, .tooOld,
             "the device's firmware is too old for this app: flash it"),
            (#"{"t":"hello","kit":0,"app":"pip","id":"i","fw":"0","does":["react"]}"#, .tooOld,
             "the device's firmware is too old for this app: flash it"),
            (#"{"t":"hello","kit":1,"app":"lamp","id":"i","fw":"1","does":["react"]}"#, .otherApp(device: "lamp", host: "pip"),
             "the device's firmware is for another app (lamp), not pip: flash it"),
            (#"{"t":"hello","kit":1,"app":"","id":"i","fw":"1","does":["react"]}"#, .otherApp(device: "", host: "pip"),
             "the device's firmware is for another app (unnamed), not pip: flash it"),
        ]
        for (line, trouble, why) in cases {
            let (link, transport, logs) = makeLink(hello: false)
            link.update(state: fields, now: 0)
            transport.clear()
            var hellos = 0
            link.onHello = { _ in hellos += 1 }
            var events = 0
            link.onEvent = { _ in events += 1 }
            link.receive(line, now: 100)
            #expect(link.trouble == trouble)
            #expect(link.trouble?.description == why)
            #expect(link.hello == nil)
            #expect(hellos == 0)
            #expect(logs.all.contains { $0.hasPrefix("device link: i firmware ") && $0.hasSuffix(why) }, "\(logs.all)")
            link.receive(#"{"t":"ev","kind":"tap"}"#, now: 150)
            link.tick(now: 20_000)
            #expect(events == 0)
            #expect(link.do("react", now: 20_000) { _ in } == nil)
            #expect(transport.types() == ["state", "state"], "the hello's answer and the keepalive, no do: \(line)")
        }
    }

    /// A `do` waiting when the device turns out not to fit fails, since
    /// nothing more goes to it and its answer can't be trusted.
    @Test func testTroubleFailsWhatWaits() {
        let (link, _, _) = makeLink()
        let outcomes = Box<DeviceLink.Outcome>()
        link.do("react", now: 0) { outcomes.add($0) }
        link.receive(#"{"t":"hello","kit":2,"app":"pip","id":"i","fw":"9","does":["react"]}"#, now: 10)
        link.receive(helloLine, now: 20)
        link.do("react", now: 30) { outcomes.add($0) }
        link.receive(#"{"t":"hello","app":"pip","id":"i","fw":"0","does":["react"]}"#, now: 40)
        #expect(outcomes.all == [.failed(.incompatible), .failed(.incompatible)])
    }

    /// `onHello` hears the first hello on a link and each that changes,
    /// not the ones that repeat every 60 s. A drop forgets it, and the
    /// trouble with it.
    @Test func testOnHelloHearsNewHellos() {
        let (link, _, _) = makeLink(hello: false)
        let heard = Box<String>()
        link.onHello = { heard.add($0.fw) }
        link.receive(helloLine, now: 0)
        link.receive(helloLine, now: 60_000)
        link.receive(helloLine.replacingOccurrences(of: "1.0.0", with: "1.0.1"), now: 61_000)
        #expect(heard.all == ["1.0.0", "1.0.1"])
        link.connection(false, now: 62_000)
        #expect(link.hello == nil)
        link.connection(true, now: 63_000)
        link.receive(helloLine, now: 63_100)
        #expect(heard.all == ["1.0.0", "1.0.1", "1.0.0"])

        link.receive(#"{"t":"hello","kit":2,"app":"pip","id":"i","fw":"9","does":["react"]}"#, now: 64_000)
        #expect(link.trouble == .tooNew)
        #expect(link.trouble != nil)
        link.connection(false, now: 65_000)
        #expect(link.trouble == nil)
    }
}

@Suite struct LinkDoTests {
    /// SPEC.md §3: ids start somewhere random each launch and count up,
    /// within 1…2147483647.
    @Test func testIdsStartSomewhereRandomAndCountUp() {
        let firsts = (0..<8).map { _ -> Int in
            let (link, _, _) = makeLink()
            let first = link.do("react", now: 0) { _ in }!
            #expect((1...Wire.maxId).contains(first))
            #expect(link.do("react", now: 0) { _ in } == DeviceLink.after(first))
            return first
        }
        #expect(Set(firsts).count > 1, "each launch starts somewhere else")
    }

    /// SPEC.md §9: ids wrap from 2147483647 to 1, skipping one still
    /// waiting.
    @Test func testIdsWrapToOne() {
        let (link, transport, _) = makeLink()
        link.nextId = 1
        #expect(link.do("react", now: 0) { _ in } == 1)
        link.nextId = Wire.maxId
        #expect(link.do("react", now: 0) { _ in } == Wire.maxId)
        #expect(link.do("react", now: 0) { _ in } == 2, "1 still waits")
        #expect(transport.dos.map { $0["id"]?.int } == [1, Wire.maxId, 2])
    }

    /// SPEC.md §3–4: every `do` gets exactly one answer: the `ended` for
    /// its id. Another for the same id, or one for an id nothing waits on,
    /// is ignored.
    @Test func testEachDoGetsExactlyOneOutcome() {
        let (link, transport, _) = makeLink()
        let outcomes = Box<(Int, DeviceLink.Outcome)>()
        let a = link.do("react", args: ["say": ["take": "x"]], now: 0) { outcomes.add((1, $0)) }!
        let b = link.do("cheer", play: .now, now: 0) { outcomes.add((2, $0)) }!
        #expect(transport.sent == [Wire.do(id: a, name: "react", play: .next, ttl: 5000, args: ["say": ["take": "x"]]),
                                   Wire.do(id: b, name: "cheer", play: .now, ttl: 5000, args: [:])])
        link.receive(ended(b, "cut", "tap"), now: 100)
        link.receive(ended(b, "done"), now: 110)
        link.receive(ended(a, "skipped", "late"), now: 5000)
        link.receive(ended(12345, "done"), now: 5000)
        link.tick(now: 1_000_000)
        link.connection(false, now: 1_000_001)
        #expect(outcomes.all.map(\.0) == [2, 1])
        #expect(outcomes.all.map(\.1) == [.ended(Ended(id: b, how: .cut, why: "tap")),
                                          .ended(Ended(id: a, how: .skipped, why: "late"))])
        #expect(link.waiting.isEmpty)
    }

    /// SPEC.md §5: with no `ended` by its `ttl` plus 60 s the host gives
    /// up, and not a millisecond sooner; a `do` that doesn't say its ttl
    /// has 5 s. An `ended` that comes later is ignored.
    @Test func testTheHostGivesUpAtTTLPlusSixtySeconds() {
        let (link, _, logs) = makeLink()
        let outcomes = Box<String>()
        link.do("react", ttl: 2000, now: 1000) { outcomes.add("next \($0)") }
        let free = link.do("cheer", play: .ifFree, ttl: 30_000, now: 1000) { outcomes.add("if_free \($0)") }!
        link.tick(now: 1000 + 2000 + 59_999)
        #expect(outcomes.all.isEmpty)
        link.tick(now: 1000 + 2000 + 60_000)
        #expect(outcomes.all == ["next \(DeviceLink.Outcome.failed(.noAnswer))"])
        link.tick(now: 1000 + 5000 + 59_999)
        #expect(outcomes.all.count == 1, "if_free leaves its ttl out, so it has the default")
        link.tick(now: 1000 + 5000 + 60_000)
        #expect(outcomes.all.count == 2)
        link.receive(ended(free, "done"), now: 70_000)
        #expect(outcomes.all.count == 2)
        #expect(logs.all.contains { $0.contains("no ended for do \(free) (cheer): gave up") })
        #expect(DeviceLink.answerGraceMs == 60_000)
    }

    /// SPEC.md §3, §9: `ttl` is 1–60000 ms; the host keeps it in range, so
    /// it gives up when the device would.
    @Test func testTTLIsKeptInRange() {
        let (link, transport, _) = makeLink()
        link.do("react", ttl: 0, now: 0) { _ in }
        link.do("react", ttl: 600_000, now: 0) { _ in }
        #expect(transport.dos.map { $0["ttl"]?.int } == [1, 60_000])
        link.tick(now: 60_000)
        #expect(link.waiting.count == 2)
        link.tick(now: 60_001)
        #expect(link.waiting.count == 1)
        link.tick(now: 120_000)
        #expect(link.waiting.isEmpty)
    }

    /// SPEC.md §5: when the link drops every `do` waiting for its `ended`
    /// fails, oldest first, before `onConnection` hears of it.
    @Test func testALinkDropFailsEverythingWaiting() {
        let (link, _, _) = makeLink()
        let heard = Box<String>()
        link.onConnection = { heard.add("connection \($0)") }
        for name in ["react", "cheer", "listening"] {
            link.do(name, now: 0) { heard.add("\(name) \($0)") }
        }
        link.connection(false, now: 10)
        let failed = DeviceLink.Outcome.failed(.disconnected)
        #expect(heard.all == ["react \(failed)", "cheer \(failed)", "listening \(failed)", "connection false"])
        #expect(link.waiting.isEmpty)
        link.connection(false, now: 20)
        #expect(heard.all.count == 4, "a drop is heard once")
    }

    /// SPEC.md §3: a name not in `hello.does` would come back `skipped`,
    /// `unknown`, so it fails at once and nothing goes out; so does a `do`
    /// with no link, before a hello, or longer than 512 bytes.
    @Test func testADoThatCantPlayFailsAtOnce() {
        func attempt(_ link: DeviceLink, _ name: String = "react", args: JSONObject = [:]) -> DeviceLink.Outcome? {
            var outcome: DeviceLink.Outcome?
            #expect(link.do(name, args: args, now: 0) { outcome = $0 } == nil)
            return outcome
        }
        let (link, transport, _) = makeLink()
        #expect(attempt(link, "dance") == .failed(.unknownName))
        #expect(attempt(link, args: ["text": .string(String(repeating: "x", count: 500))]) == .failed(.tooLong))
        #expect(transport.sent.isEmpty)
        #expect(attempt(makeLink(hello: false).0) == .failed(.noHello))
        #expect(attempt(makeLink(connected: false, hello: false).0) == .failed(.notConnected))
        #expect(attempt(makeLink(connected: false).0) == .failed(.notConnected), "a hello with no link up")
    }

    /// Callbacks run after the link's own bookkeeping, so one may ask for
    /// the next `do` at once.
    @Test func testACompletionMayAskForTheNext() {
        let (link, transport, _) = makeLink()
        var second: Int?
        let first = link.do("react", now: 0) { _ in second = link.do("cheer", now: 1) { _ in } }!
        link.receive(ended(first, "done"), now: 1)
        #expect(second == DeviceLink.after(first))
        #expect(transport.dos.count == 2)
        #expect(link.waiting.keys.sorted() == [second!])
    }
}

@Suite struct LinkEventTests {
    /// SPEC.md §3: every `ev` but `ended` goes to `onEvent`, with what the
    /// device did and the app's data.
    @Test func testEveryEventButEndedGoesToOnEvent() {
        let (link, _, _) = makeLink()
        let events = Box<DeviceEvent>()
        link.onEvent = { events.add($0) }
        let id = link.do("react", now: 0) { _ in }!
        for line in [#"{"t":"ev","kind":"tap","did":"poked"}"#,
                     #"{"t":"ev","kind":"tap","did":"dip","data":{"on":44}}"#,
                     ended(id, "done"),
                     ended(999, "done"),
                     #"{"t":"ev","kind":"talk_on","did":"listening"}"#,
                     #"{"t":"dbg.ping","up":5}"#] {
            link.receive(line, now: 10)
        }
        #expect(events.all == [DeviceEvent(kind: "tap", did: "poked"),
                               DeviceEvent(kind: "tap", did: "dip", data: ["on": 44]),
                               DeviceEvent(kind: "talk_on", did: "listening")])
        #expect(events.all[1].data["on"]?.int == 44)
    }

    /// `receive` says what each message was, for the owner's log.
    @Test func testReceiveSaysWhatTheLineWas() {
        let (link, _, _) = makeLink()
        let id = link.do("react", now: 0) { _ in }!
        #expect(link.receive(ended(id, "cut", "now"), now: 1) == .ended(Ended(id: id, how: .cut, why: "now")))
        #expect(link.receive("boot noise", now: 1) == .other("boot noise"))
    }
}
