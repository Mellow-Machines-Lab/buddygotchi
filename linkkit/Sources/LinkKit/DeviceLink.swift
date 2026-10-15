import Foundation

/// The host's side of the protocol (SPEC.md §5): keeps the device's
/// picture true with `state`, asks it to play things with `do` and hands
/// on what it says.
///
/// - `state`: sent on every change, at once when the link comes up, in
///   answer to every `hello`, and again once 10 s have passed (`tick`).
///   One longer than 512 bytes is never sent (SPEC.md §2): the last that
///   fit stands.
/// - `hello`: asked for (the host's bare `{"t":"hello"}`, SPEC.md §3) when
///   the link comes up, and again every 10 s until one comes, since a
///   device that still counts the host as there (an app relaunched within
///   30 s, or one taking over a Bluetooth link macOS kept) doesn't say it
///   unasked. Checked against the kit's version and the app's name. A
///   device that doesn't fit (a `kit` other than 1, or another app) still
///   gets `state`, so a device flashed while the link stays up hears the
///   host and says its new `hello`, but no `do`, and its `ev`s are
///   dropped: `trouble` says why.
/// - `do`: each gets an id and exactly one `Outcome`: the device's
///   `ended`, or a failure here (no link, no hello yet, a name the device
///   doesn't play, the link dropping, no answer by its `ttl` plus 60 s).
/// - `ev`: every one but `ended` goes to `onEvent`, from a device that fits.
///
/// Call everything on one queue. A transport calls back on its own thread,
/// so the owner hops to that queue and passes each line to `receive` and
/// each change of connection to `connection`, and calls `tick` about once
/// a second. Every call takes the owner's clock, in ms:
///
/// ```swift
/// let link = DeviceLink(app: "lamp", transport: SocketTransport(path: "/tmp/lamp.sock"))
/// link.onEvent = { ev in if ev.kind == "tap" { … } }
/// link.transport?.start(onLine: { line in queue.async { link.receive(line, now: clock()) } },
///                       onConnection: { up in queue.async { link.connection(up, now: clock()) } })
/// link.update(state: ["level": 40], now: clock())
/// link.do("blink", args: ["times": 2], now: clock()) { outcome in … }
/// ```
///
/// Callbacks run on the owner's queue, inside the call that caused them,
/// after the link's own bookkeeping, so they may call back into the link.
///
/// Not `Link`, which SwiftUI already names: an app's views import both.
public final class DeviceLink {
    /// A `state` goes out at least this often (SPEC.md §5).
    public static let keepaliveMs: Int64 = 10_000
    /// A `do` with no `ended` this long after its `ttl` has passed is given
    /// up: a message was lost (SPEC.md §5).
    public static let answerGraceMs: Int64 = 60_000

    /// Who asked for a message, passed to `onSend` as it is (a debug log's
    /// tracing): the link makes nothing of it. The app names its own
    /// senders (`by:` on `do`, `app` when it doesn't say); the link's own
    /// messages are `link`.
    public struct Sender: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let name: String
        public init(_ name: String) { self.name = name }
        public init(stringLiteral name: String) { self.name = name }
        public var description: String { name }

        /// A `do` whose app didn't say who asked for it.
        public static let app: Sender = "app"
        /// The link's own messages: every `state` (the link decides when one
        /// goes out) and its ask for the device's `hello`.
        public static let link: Sender = "link"
    }

    /// Why the device on the link gets no `do` (SPEC.md §6): its firmware
    /// doesn't fit this app. `description` says it in plain words, with
    /// what to do.
    public enum Trouble: Equatable, Sendable, CustomStringConvertible {
        /// Firmware older than the host: its `kit` is below 1 or missing.
        case tooOld
        /// A `kit` newer than the host speaks.
        case tooNew
        /// Firmware for another app: its `hello.app`, and this host's.
        case otherApp(device: String, host: String)

        public var description: String {
            switch self {
            case .tooOld: "the device's firmware is too old for this app: flash it"
            case .tooNew: "the device's firmware is too new for this app: update the app"
            case .otherApp(let device, let host):
                "the device's firmware is for another app (\(device.isEmpty ? "unnamed" : device)), not \(host): flash it"
            }
        }
    }

    /// Why a `do` has no `ended` from the device.
    public enum Failure: Equatable, Sendable, CustomStringConvertible {
        /// No link to the device when it was asked for. Nothing was sent.
        case notConnected
        /// The device hasn't said `hello` on this link yet. Nothing was sent.
        case noHello
        /// The device's firmware doesn't fit this app (`trouble`). Nothing
        /// was sent, or it was waiting when that turned out.
        case incompatible
        /// The name isn't in the device's `hello.does`. Nothing was sent.
        case unknownName
        /// The message would be longer than 512 bytes, which the device drops.
        /// Nothing was sent.
        case tooLong
        /// The link dropped while it waited for its `ended`. The device
        /// may play on.
        case disconnected
        /// No `ended` came by its `ttl` plus 60 s.
        case noAnswer
        /// The device restarted while it waited (a `hello` with a new
        /// `boot`): it has forgotten the `do`.
        case restarted

        public var description: String {
            switch self {
            case .notConnected: "no device connected"
            case .noHello: "the device hasn't said hello"
            case .incompatible: "the device's firmware doesn't fit this app"
            case .unknownName: "the device doesn't play that"
            case .tooLong: "the line is too long"
            case .disconnected: "the device disconnected"
            case .noAnswer: "the device never said it ended"
            case .restarted: "the device restarted"
            }
        }
    }

    /// How a `do` came out: the device's answer, or why there's none.
    public enum Outcome: Equatable, Sendable {
        case ended(Ended)
        case failed(Failure)
    }

    /// The `hello.app` this host drives: `lamp`.
    public let app: String
    public let transport: Transport?
    public private(set) var connected = false
    /// The device's latest `hello` on this link, when it fits this app.
    /// Nil until one comes, after the link drops, and while `trouble` is set.
    public private(set) var hello: Hello?
    /// The last `boot` a fitting `hello` gave, kept across links: a
    /// different one means the device restarted (SPEC.md §5).
    public private(set) var lastBoot: String?
    /// Why the device on the link gets no `do` (SPEC.md §6); nil when it
    /// fits or hasn't said. It still gets `state`. Cleared when the link
    /// drops or a `hello` that fits comes.
    public private(set) var trouble: Trouble?
    /// The app's latest `state` fields that fit in a message.
    public private(set) var state: JSONObject?

    /// Every `ev` but `ended`, from a device that fits: while `trouble` is
    /// set they're dropped, since they're another firmware's words.
    public var onEvent: ((DeviceEvent) -> Void)?
    /// A `hello` that fits, when it isn't the one the link already has:
    /// the first on a link, or one that changed.
    public var onHello: ((Hello) -> Void)?
    /// The link came up or dropped. On a drop, after every waiting `do`
    /// has failed.
    public var onConnection: ((Bool) -> Void)?
    /// Every message sent, with who asked for it.
    public var onSend: ((String, Sender) -> Void)?

    let log: (String) -> Void
    /// `state` as a message, and the last one sent and when.
    var stateLine: String?
    var lastSentLine: String?
    var lastSentAt: Int64?
    /// The next `do`'s id.
    var nextId: Int
    /// The `do`s sent that wait for their `ended`, by id.
    var waiting: [Int: Waiting] = [:]
    /// Counts `do`s sent, to fail the waiting ones in the order they went.
    var sentCount = 0
    /// The last overlong `state` logged, so it's logged once.
    var warnedLine: String?
    /// When the host last asked for the device's `hello`.
    var askedAt: Int64?

    struct Waiting {
        let name: String
        let order: Int
        let giveUpAt: Int64
        let completion: (Outcome) -> Void
    }

    /// `app` is the `hello.app` this host drives. With no transport the
    /// link is never up, and every `do` fails at once.
    public init(app: String, transport: Transport?, log: @escaping (String) -> Void = { _ in }) {
        self.app = app
        self.transport = transport
        self.log = log
        // Somewhere random each launch, so an id an earlier launch left on
        // the device isn't reused (SPEC.md §3).
        nextId = Int.random(in: 1...Wire.maxId)
    }

    // MARK: - State

    /// The app's `state` fields, in the order they go in the message.
    /// Sent only if it differs from the last one sent. Give the link one
    /// from the start: the device says `hello` only once it hears the host
    /// (SPEC.md §5), and until then every `do` fails. Fields too long for a
    /// message are never sent, since the device would drop them whole
    /// (SPEC.md §2): logged once, and the last that fit stands.
    public func update(state fields: JSONObject, now: Int64) {
        let line = Wire.state(fields)
        guard line.utf8.count <= Wire.maxLine else {
            if warnedLine != line {
                warnedLine = line
                log("device link: a state line of \(line.utf8.count) bytes is over \(Wire.maxLine): not sent")
            }
            return
        }
        state = fields
        stateLine = line
        guard line != lastSentLine else { return }
        sendState(now: now)
    }

    /// About once a second: sends the latest `state` again once 10 s have
    /// passed without one, asks again for a `hello` that hasn't come, and
    /// gives up on each `do` whose `ended` is overdue.
    public func tick(now: Int64) {
        let overdue = waiting.filter { $0.value.giveUpAt <= now }.sorted { $0.value.order < $1.value.order }
        for (id, w) in overdue {
            waiting[id] = nil
            log("device link: no ended for do \(id) (\(w.name)): gave up")
        }
        if askedAt.map({ now - $0 >= Self.keepaliveMs }) ?? true { askHello(now: now) }
        if lastSentAt.map({ now - $0 >= Self.keepaliveMs }) ?? true { sendState(now: now) }
        for (_, w) in overdue { w.completion(.failed(.noAnswer)) }
    }

    func sendState(now: Int64) {
        guard let line = stateLine else { return }
        lastSentLine = line
        lastSentAt = now
        send(line, by: .link)
    }

    /// Asks the device for its `hello` while the link is up and it hasn't
    /// said one, fitting or not (SPEC.md §3). The device answers the host's
    /// `hello` with its own on that link, and only once if the ask is also
    /// the first message it hears from the host, so the ask goes before a
    /// `state` (SPEC.md §5).
    func askHello(now: Int64) {
        guard connected, hello == nil, trouble == nil else { return }
        askedAt = now
        send(Wire.hello, by: .link)
    }

    // MARK: - Do

    /// Asks the device to play `name`, one of its `hello.does`, with the
    /// app's `args`. `ttl` (1–60000 ms) is how long a `next` may wait in
    /// the queue; `now` and `if_free` don't wait, and the message leaves it out.
    ///
    /// `completion` runs exactly once: with the device's `ended`, or a
    /// failure. When the `do` can't be sent it runs before this returns,
    /// and the result is nil; otherwise the result is the `do`'s id.
    @discardableResult
    public func `do`(_ name: String, args: JSONObject = [:], play: Wire.Play = .next, ttl: Int = Wire.defaultTTL,
                     by sender: Sender = .app, now: Int64, _ completion: @escaping (Outcome) -> Void) -> Int? {
        let ttl = min(max(ttl, 1), Wire.maxTTL)
        var id = nextId
        while waiting[id] != nil { id = Self.after(id) }
        let line = Wire.do(id: id, name: name, play: play, ttl: ttl, args: args)
        let failure: Failure? =
            if !connected { .notConnected }
            else if trouble != nil { .incompatible }
            else if let hello { hello.does.contains(name) ? nil : .unknownName }
            else { .noHello }
        if let failure = failure ?? (line.utf8.count > Wire.maxLine ? .tooLong : nil) {
            completion(.failed(failure))
            return nil
        }
        nextId = Self.after(id)
        sentCount += 1
        // A `do` that doesn't say its ttl has the default one (SPEC.md §3).
        let waits = Int64(play == .next ? ttl : Wire.defaultTTL)
        waiting[id] = Waiting(name: name, order: sentCount, giveUpAt: now + waits + Self.answerGraceMs,
                              completion: completion)
        send(line, by: sender)
        return id
    }

    /// Ids count up and wrap from 2147483647 to 1.
    static func after(_ id: Int) -> Int { id >= Wire.maxId ? 1 : id + 1 }

    /// Removes every waiting `do`, oldest first.
    func takeWaiting() -> [Waiting] {
        let all = waiting.values.sorted { $0.order < $1.order }
        waiting.removeAll()
        return all
    }

    // MARK: - From the device

    /// A message from the device. Answers `hello` with the latest `state`,
    /// finishes the `do` an `ended` names, and passes other `ev`s to
    /// `onEvent`. Returns what the message was, for the owner's log, and
    /// for the app to read a message the kit doesn't know (`.other`).
    @discardableResult
    public func receive(_ line: String, now: Int64) -> Wire.Message {
        let message = Wire.decode(line)
        switch message {
        case .hello(let h):
            if let why = problem(with: h) {
                meetTrouble(why, from: h)
                sendState(now: now)
            } else {
                let changed = hello != h
                hello = h
                trouble = nil
                // A device that restarted has forgotten what it was asked
                // (SPEC.md §5): what waits on it fails at once.
                var forgotten: [Waiting] = []
                if let boot = h.boot {
                    if let last = lastBoot, last != boot {
                        forgotten = takeWaiting()
                        log("device link: the device restarted (boot \(last) → \(boot))")
                    }
                    lastBoot = boot
                }
                // A device that rebooted catches up at once (SPEC.md §5).
                sendState(now: now)
                for w in forgotten { w.completion(.failed(.restarted)) }
                if changed { onHello?(h) }
            }
        case .ended(let ended):
            // One that isn't waiting was answered already or given up on.
            if let w = waiting.removeValue(forKey: ended.id) { w.completion(.ended(ended)) }
        case .event(let event):
            if trouble == nil { onEvent?(event) }
        case .other:
            break
        }
        return message
    }

    /// The transport connected or dropped. On connect the device is asked
    /// for its `hello` and gets the latest `state` at once; on a drop every
    /// waiting `do` fails.
    public func connection(_ up: Bool, now: Int64) {
        guard up != connected else { return }
        connected = up
        log("device link: \(up ? "connected" : "disconnected") (\(transport?.name ?? "none"))")
        var dropped: [Waiting] = []
        if up {
            askHello(now: now)
            sendState(now: now)
        } else {
            hello = nil
            trouble = nil
            dropped = takeWaiting()
        }
        for w in dropped { w.completion(.failed(.disconnected)) }
        onConnection?(up)
    }

    // MARK: - Trouble

    /// Why a `hello` doesn't fit (SPEC.md §6), or nil when it does.
    func problem(with hello: Hello) -> Trouble? {
        guard let kit = hello.kit, kit >= Wire.kit else { return .tooOld }
        guard kit == Wire.kit else { return .tooNew }
        guard hello.app == app else { return .otherApp(device: hello.app, host: app) }
        return nil
    }

    /// The device doesn't fit: it gets no `do`, and what waited on it
    /// fails. Logged once for each new reason, with who said the `hello`
    /// that didn't fit.
    func meetTrouble(_ why: Trouble, from misfit: Hello) {
        hello = nil
        if trouble != why {
            trouble = why
            log("device link: " + (misfit.id.isEmpty ? "" : "\(misfit.id) firmware \(misfit.fw): ") + why.description)
        }
        for w in takeWaiting() { w.completion(.failed(.incompatible)) }
    }

    func send(_ line: String, by sender: Sender) {
        onSend?(line, sender)
        transport?.send(line)
    }
}
