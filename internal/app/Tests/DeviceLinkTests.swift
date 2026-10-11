import AgentHooks
import CoreBluetooth
import Foundation
import LinkKit
import XCTest
@testable import BoopKit

/// Plays Boop's device over a fake transport, as
/// linkkit/device's kit does: records what the link sends, says `hello`
/// when the app speaks on a link where the device doesn't count it as
/// there yet (for Bluetooth, its first line since connecting) and whenever
/// the app asks with its own `hello`, and lets a test send the device's
/// lines. LinkKit's own tests (`linkkit/Tests`) cover the link, its ids and
/// its transports.
final class FakeTransport: Transport, @unchecked Sendable {
    /// Boop's device, playing every name the app sends, with the app's
    /// voice pack.
    static let hello = #"{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.0.0","does":["react","task_complete","reply_ready","starting","stopped","error","helper_return","listening","stop_listening","poked","tap_spam"],"voice":"\#(Take.packVersion)"}"#

    let lock = NSLock()
    var lines: [String] = []
    var onLine: (@Sendable (String) -> Void)?
    var onConnection: (@Sendable (Bool) -> Void)?
    var name: String { "fake" }
    var why: String?
    var trouble: String? { lock.withLock { why } }
    /// What the device says when the app first speaks on a link; nil says
    /// nothing. A `hello` also answers the app's ask; firmware from before
    /// the kit, which says `status`, ignores the ask.
    var greeting: String? = FakeTransport.hello
    /// Whether the device sees the link drop, so the app's next line is new
    /// to it (a Bluetooth connect). False plays a device that still counts
    /// the app as there: an app relaunched within 30 s over USB, or one
    /// taking over the Bluetooth link macOS kept.
    var seesDrops = true
    /// The link is up, and the device counts the app as there on it.
    var up = false
    var heard = false

    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        self.onLine = onLine
        self.onConnection = { [weak self] up in
            self?.lock.withLock {
                self?.up = up
                if self?.seesDrops == true { self?.heard = false }
            }
            onConnection(up)
        }
    }

    func send(_ line: String) {
        let reply = lock.withLock { () -> String? in
            lines.append(line)
            guard up, let greeting = self.greeting else { return nil }
            let new = !heard
            heard = true
            let asked = line == Wire.hello && greeting.hasPrefix(#"{"t":"hello""#)
            return new || asked ? greeting : nil
        }
        if let reply { onLine?(reply) }
    }

    func reconnect() {}
    func stop() {}

    var sent: [String] { lock.withLock { lines } }
    func types() -> [String] {
        sent.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["t"] as? String }
    }

    /// The `do` lines sent, in order.
    var dos: [String] { sent.filter { $0.hasPrefix(#"{"t":"do""#) } }
    /// The `do` lines sent for `name`.
    func dos(_ name: String) -> [String] { dos.filter { $0.contains(#""name":"\#(name)""#) } }
    /// A `do` line's id.
    static func id(_ line: String) -> Int {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int ?? 0
    }

    var answered: Set<Int> = []

    /// Answers every `do` not answered yet with its `ended`, as the device
    /// does once it's over (linkkit/SPEC.md §4).
    func endDos(_ how: String = "done", why: String? = nil) {
        for id in dos.map(Self.id) where lock.withLock({ answered.insert(id).inserted }) {
            onLine?(Self.ended(id, how, why))
        }
    }

    /// The device's `ended` for `id`.
    static func ended(_ id: Int, _ how: String, _ why: String? = nil) -> String {
        #"{"t":"ev","kind":"ended","data":{"id":\#(id),"how":"\#(how)""# + (why.map { #","why":"\#($0)""# } ?? "") + "}}"
    }
}

func sampleSnapshot(busy: Int = 0) -> StateSnapshot {
    StateSnapshot(base: busy > 0 ? "working" : "idle", mood: "happy", attn: nil, busy: busy, vol: 6)
}

/// Boop's vocabulary on LinkKit: its `state` and `do` lines,
/// what its `hello` and taps mean, and the `--link` setting.
extension DeviceMoment {
    /// The `do` line the link sends for it, with `id` and `play`: what the
    /// device reads.
    func line(id: Int, play: Wire.Play, ttl: Int = Wire.defaultTTL) -> String {
        Wire.do(id: id, name: name, play: play, ttl: ttl, args: args)
    }
}

final class DeviceLinkTests: XCTestCase {
    override func setUpWithError() throws { try requireBoopsPack() }

    /// The device's `hello` says who it is and which voice
    /// pack its card has; a tap names the brain's finish it landed on, when
    /// it only dipped the face.
    func testWhatTheDeviceSays() throws {
        let hello = try XCTUnwrap({ if case .hello(let h) = Wire.decode(FakeTransport.hello) { h } else { nil } }())
        XCTAssertEqual(DeviceInfo(hello), DeviceInfo(id: "b00p-54fe", fw: "1.0.0", voice: Take.packVersion))
        XCTAssertEqual(hello.app, BoopDevice.app)
        func tap(_ line: String) -> Int?? {
            guard case .event(let ev) = Wire.decode(line), ev.kind == "tap" else { return .none }
            return .some(BoopDevice.finish(tapped: ev))
        }
        XCTAssertEqual(tap(#"{"t":"ev","kind":"tap","did":"poked"}"#), .some(nil))
        XCTAssertEqual(tap(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":42}}"#), .some(42))
        XCTAssertEqual(tap(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":0}}"#), .some(nil), "no finish")
        XCTAssertEqual(tap(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":"42"}}"#), .some(nil))
        XCTAssertEqual(Wire.decode(FakeTransport.ended(5, "cut", "tap")), .ended(Ended(id: 5, how: .cut, why: "tap")))
    }

    /// Each moment's `do`, with its name and its `args` in
    /// the protocol's order, every string escaped. A brain reaction with no
    /// animation is `react`, and still has a `say`: the reply that ends
    /// push-to-talk's listening. The longest one fits in a line.
    func testDoLinesMatchTheProtocol() {
        XCTAssertEqual(DeviceMoment(say: .go, mood: "proud", loops: 1).line(id: 558386700, play: .next),
                       #"{"t":"do","id":558386700,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d02"},"mood":"proud","loops":1}}"#)
        XCTAssertEqual(DeviceMoment(say: .init(takes: []), mood: "calm", loops: 1).line(id: 5, play: .next),
                       #"{"t":"do","id":5,"name":"react","play":"next","ttl":5000,"args":{"say":{},"mood":"calm","loops":1}}"#)
        XCTAssertEqual(DeviceMoment(anim: "starting", variant: 3, ctx: "new_task").line(id: 558386701, play: .ifFree),
                       #"{"t":"do","id":558386701,"name":"starting","play":"if_free","args":{"variant":3,"ctx":"new_task"}}"#)
        XCTAssertEqual(DeviceMoment(anim: "stopped").line(id: 9, play: .ifFree), #"{"t":"do","id":9,"name":"stopped","play":"if_free"}"#)
        let finish = DeviceMoment(anim: "task_complete", say: .go, mood: "proud", variant: 2,
                                  who: .init(agent: "claude", thread: "api"), outcome: "success")
        XCTAssertEqual(finish.line(id: 558386703, play: .next),
                       #"{"t":"do","id":558386703,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","variant":2,"who":{"agent":"claude","thread":"api"},"say":{"take":"new.d02"},"mood":"proud"}}"#)
        // A finish names whose turn it was, the thread cut as names are and
        // escaped; the thread it opens isn't sent.
        let quoted = DeviceMoment(anim: "reply_ready", variant: 1,
                                  who: .init(agent: "codex", thread: #"fix "nav"\"#, opens: ThreadRef(agent: "codex", session: "s")))
        XCTAssertEqual(quoted.args.json, #"{"variant":1,"who":{"agent":"codex","thread":"fix \"nav\"\\"}}"#)
        XCTAssertEqual(DeviceMoment.Who(agent: "claude", thread: "claude/cheer-animation-thread-codex").thread, "claude/cheer-animatio..")
        let byLength = Take.all.sorted { $0.id.utf8.count > $1.id.utf8.count }
        let longest = DeviceMoment.Say(takes: [byLength[0], byLength[1]])
        let longestWho = DeviceMoment.Who(agent: "claude", thread: String(repeating: "\"", count: 23))
        XCTAssertLessThanOrEqual(DeviceMoment(anim: "task_complete", say: longest, mood: "determined", loops: DeviceMoment.maxLoops,
                                              variant: 5, who: longestWho, outcome: "failure")
                                     .line(id: Wire.maxId, play: .next).utf8.count, Wire.maxLine)
    }

    /// linkkit/SPEC.md §5–6 in Boop's words: the link asks for the device's
    /// `hello` and sends the latest `state` when it connects, answers the
    /// `hello` with the `state`, and takes only Boop's firmware. Firmware
    /// from before the kit says `status` where a `hello` would be, which
    /// Boop spots itself (the kit leaves that to the app): it still gets
    /// its `state` but no `do`, and the popover says to flash it.
    func testTheLinkTakesBoopsFirmware() {
        let transport = FakeTransport()
        transport.start(onLine: { _ in }, onConnection: { _ in })
        let link = BoopDevice.link(transport)
        link.update(state: sampleSnapshot(busy: 2).fields, now: 0)
        link.connection(true, now: 100)
        XCTAssertEqual(link.receive(FakeTransport.hello, now: 200).isHello, true)
        XCTAssertEqual(transport.types(), ["state", "hello", "state", "state"],
                       "sent into nothing, then the ask and the state on connect, then the state for the hello")
        XCTAssertEqual(transport.sent.last, sampleSnapshot(busy: 2).jsonLine)
        XCTAssertEqual(link.hello.map(DeviceInfo.init)?.id, "b00p-54fe")
        XCTAssertNotNil(link.do("react", args: DeviceMoment(say: .go).args, now: 300) { _ in })

        let status = #"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1"}"#
        XCTAssertEqual(link.receive(status, now: 400), .other(status), "LinkKit leaves it to the app")
        XCTAssertEqual(BoopDevice.fromBeforeTheKit(status), DeviceInfo(id: "b00p-7f3a", fw: "0.3.1"))
        XCTAssertNil(BoopDevice.fromBeforeTheKit(FakeTransport.hello))
        XCTAssertNil(BoopDevice.fromBeforeTheKit("rst:0x1 (POWERON_RESET)"))
        link.incompatible(.tooOld, now: 400)
        XCTAssertEqual(link.trouble, .tooOld)
        XCTAssertEqual(link.trouble?.description, "the device's firmware is too old for this app: flash it")
        XCTAssertNil(link.hello)
        var outcome: DeviceLink.Outcome?
        XCTAssertNil(link.do("react", now: 500) { outcome = $0 })
        XCTAssertEqual(outcome, .failed(.incompatible))
        XCTAssertEqual(transport.types().last, "state", "it still gets the state")
        link.connection(false, now: 600)
        XCTAssertNil(link.trouble)
    }

    /// The fake device's `hello.does` is the firmware's
    /// (`kDoNames` in firmware/src/app/device.cpp, in its order), and every
    /// name the Mac sends is among them: LinkKit fails a `do` whose name the
    /// `hello` doesn't list, so a name the firmware drops or renames would
    /// silently cost Boop that one-shot, or every reaction.
    func testTheMacSendsOnlyNamesTheFirmwarePlays() throws {
        let device = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../firmware/src/app/device.cpp").standardizedFileURL
        let source = try String(contentsOf: device, encoding: .utf8)
        let from = try XCTUnwrap(source.range(of: "kDoNames[kDoCount] = {"))
        let to = try XCTUnwrap(source.range(of: "};", range: from.upperBound..<source.endIndex))
        let re = try NSRegularExpression(pattern: #""([a-z_]+)""#)
        let body = String(source[from.upperBound..<to.lowerBound])
        let firmware = re.matches(in: body, range: NSRange(body.startIndex..., in: body))
            .map { String(body[Range($0.range(at: 1), in: body)!]) }
        let hello = try XCTUnwrap({ if case .hello(let h) = Wire.decode(FakeTransport.hello) { h } else { nil } }())
        XCTAssertEqual(hello.does, firmware, "the fake device plays what the firmware does")
        let sent = DeviceMoment.anims + [DeviceMoment.react, BoopDevice.listening, BoopDevice.stopListening]
        XCTAssertEqual(Set(sent).subtracting(firmware), [], "every name the Mac sends is one the firmware plays")
    }

    /// Bluetooth off, refused or missing is said in plain words, with what
    /// to do, in Boop's name. Only the words: nothing here may start
    /// Bluetooth (CLAUDE.md).
    func testBluetoothThatCantBeUsedSaysWhy() {
        XCTAssertEqual(BLETransport.trouble(.poweredOff, appName: "Boop"), "Bluetooth is off. Turn it on in Control Center.")
        XCTAssertEqual(BLETransport.trouble(.unauthorized, appName: "Boop"),
                       "Boop isn't allowed to use Bluetooth. Allow it in System Settings → Privacy & Security → Bluetooth.")
        for state in [CBManagerState.poweredOn, .resetting, .unknown] { XCTAssertNil(BLETransport.trouble(state, appName: "Boop")) }
    }

    /// A card with no pack, or another pack than the app's,
    /// leaves Boop without its voice, and the log says so once for each
    /// hello that changes.
    func testACardWithoutTheAppsPackHasNoVoice() {
        let lines = Lines()
        let transport = FakeTransport()
        let link = BoopDevice.link(transport)
        link.onHello = { DeviceInfo($0).logLines.forEach(lines.add) }
        link.connection(true, now: 0)
        func hello(_ voice: String?) -> String {
            FakeTransport.hello.replacingOccurrences(of: #","voice":"\#(Take.packVersion)""#, with: voice.map { #","voice":"\#($0)""# } ?? "")
        }
        link.receive(hello("none"), now: 100)
        link.receive(hello("none"), now: 200)
        XCTAssertEqual(link.hello.map(DeviceInfo.init)?.hasTheVoice, false)
        XCTAssertEqual(lines.all.filter { $0.contains("Boop says nothing until they match") }.count, 1)
        XCTAssertEqual(lines.all.first, "device: b00p-54fe firmware 1.0.0 voice none")
        link.receive(hello("0123456789abcdef"), now: 300)
        XCTAssertEqual(link.hello.map(DeviceInfo.init)?.hasTheVoice, false)
        link.receive(hello(Take.packVersion), now: 400)
        XCTAssertEqual(link.hello.map(DeviceInfo.init)?.hasTheVoice, true)
        link.receive(hello(nil), now: 500)
        XCTAssertEqual(link.hello.map(DeviceInfo.init)?.hasTheVoice, true, "firmware that doesn't say")
    }

    /// The widest name the Mac sends: 47 bytes that JSON escapes to two
    /// each. Control characters, six bytes escaped, clip turns to spaces.
    private let widest = StateSnapshot.clip(String(repeating: "\"", count: 60), max: StateSnapshot.maxSignBytes)
    private let esc = String(repeating: #"\""#, count: 47)

    /// A line is at most 512 bytes. The biggest `state`,
    /// with a 47-byte project and name that escape to two bytes a
    /// character, fits.
    func testEveryStateLineFitsTheProtocol() {
        XCTAssertEqual(StateSnapshot.clip("a\u{1}b\u{7F}c\td"), "a b c d")
        let s = StateSnapshot(base: "working", mood: "determined",
                              attn: .init(agent: "claude", project: widest, name: widest, more: 999, id: Int(Int32.max)),
                              busy: 999, vol: 10, variant: 5)
        XCTAssertLessThanOrEqual(s.jsonLine.utf8.count, Wire.maxLine)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(s.jsonLine.utf8)))
        XCTAssertEqual(s.jsonLine, #"{"t":"state","base":"working","mood":"determined","attn":{"agent":"claude","project":"\#(esc)","name":"\#(esc)","more":999,"id":2147483647},"busy":999,"vol":10,"variant":5}"#)
        XCTAssertEqual(s.jsonLine, Wire.state(s.fields), "LinkKit's state, Boop's fields")
    }

    /// `act` goes after `base`; the widest line that can
    /// carry it, with the longest names escaped, still fits in 512 bytes.
    func testTheActivityFitsTheLine() {
        let working = StateSnapshot(base: "working", act: "delegating", mood: "happy", attn: nil, busy: 2, vol: 6, variant: 3)
        XCTAssertEqual(working.jsonLine, #"{"t":"state","base":"working","act":"delegating","mood":"happy","busy":2,"vol":6,"variant":3}"#)
        XCTAssertEqual(working.visual, "delegating")
        XCTAssertEqual(working.look, "delegating")
        let s = StateSnapshot(base: "working", act: "delegating", mood: "determined",
                              attn: .init(agent: "claude", project: widest, name: widest, more: 999, id: Int(Int32.max)),
                              busy: 999, vol: 10, variant: 9)
        XCTAssertLessThanOrEqual(s.jsonLine.utf8.count, Wire.maxLine)
        XCTAssertEqual(s.visual, "needs_you", "attn wins")
        XCTAssertLessThanOrEqual(Act.allCases.map(\.rawValue.utf8.count).max()!, "delegating".utf8.count)
    }

    /// The simulator is a body to choose only while it runs
    /// (`DeviceChooser`): chosen, the board is let go and its lines are no
    /// longer heard; when the simulator stops, Boop is back on its board
    /// by itself, within a couple of looks (`watchEvery`).
    func testASimulatorIsADeviceToChooseWhileItRuns() throws {
        let path = "/tmp/boop-test-sim-\(getpid()).sock"
        let board = FakeTransport()
        let chooser = DeviceChooser(board: board, simulatorSocket: path)
        let lines = Lines(), ups = Lines(), choices = Lines()
        chooser.onChoice { choices.add($0.rawValue) }
        chooser.start(onLine: { lines.add($0) }, onConnection: { ups.add($0 ? "up" : "down") })
        XCTAssertEqual(chooser.choice, .board)
        XCTAssertFalse(chooser.simulatorIsThere(), "nothing is running")
        board.onConnection?(true)
        board.onLine?("from the board")
        XCTAssertEqual(lines.all, ["from the board"])

        let simulator = try XCTUnwrap(EchoSocket(path))
        defer { simulator.stop() }
        XCTAssertTrue(chooser.simulatorIsThere())
        XCTAssertEqual(chooser.choice, .board, "being there doesn't choose it")
        chooser.choose(.simulator)
        XCTAssertEqual(chooser.choice, .simulator)
        XCTAssertEqual(chooser.name, "simulator")
        eventually("the board's link dropped, then the simulator's came up") { ups.all == ["up", "down", "up"] }
        board.onLine?("from the board, late")
        chooser.send("to the simulator")
        eventually("the simulator's line, and not the board's") { lines.all == ["from the board", "to the simulator"] }
        XCTAssertFalse(board.lines.contains("to the simulator"))

        simulator.stop()
        eventually("back on its board when the simulator stops", timeout: 3 * DeviceChooser.watchEvery) { chooser.choice == .board }
        XCTAssertFalse(chooser.simulatorIsThere())
        XCTAssertEqual(choices.all, ["simulator", "board"], "whoever shows the choice hears both changes")
        chooser.send("to the board")
        XCTAssertTrue(board.lines.contains("to the board"))
        chooser.stop()
    }

    func testASocketThatIsNotThereIsNoSimulator() {
        XCTAssertFalse(DeviceChooser(board: FakeTransport(), simulatorSocket: "/tmp/boop-test-no-such-\(getpid()).sock").simulatorIsThere())
        // A plain file of that name isn't one either.
        let file = "/tmp/boop-test-file-\(getpid()).sock"
        FileManager.default.createFile(atPath: file, contents: Data())
        defer { unlink(file) }
        XCTAssertFalse(DeviceChooser(board: FakeTransport(), simulatorSocket: file).simulatorIsThere())
    }

    func testLinkSettings() {
        XCTAssertEqual(LinkSetting("usb:/tmp/x.sock"), .usb("/tmp/x.sock"))
        XCTAssertEqual(LinkSetting("ble"), .bluetooth)
        XCTAssertEqual(LinkSetting("none"), LinkSetting.none)
        XCTAssertNil(LinkSetting("usb:"))
        XCTAssertNil(LinkSetting("wifi"))
    }
}

/// A simulator's cable for a test: a Unix socket that takes one
/// client and sends back whatever it's sent.
final class EchoSocket: @unchecked Sendable {
    let path: String
    let fd: Int32
    let lock = NSLock()
    var clients: [Int32] = []

    init?(_ path: String) {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else { return nil }
        let fd = fd
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                self.lock.withLock { self.clients.append(client) }
                Thread.detachNewThread {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let n = read(client, &buffer, buffer.count)
                        guard n > 0 else { break }
                        _ = write(client, buffer, n)
                    }
                    close(client)
                }
            }
        }
    }

    /// The simulator stops: its cable goes, and whoever was on it is dropped.
    func stop() {
        close(fd)
        unlink(path)
        lock.withLock { clients }.forEach { shutdown($0, SHUT_RDWR) }
    }
}

extension Wire.Message {
    var isHello: Bool {
        if case .hello = self { return true }
        return false
    }
}
