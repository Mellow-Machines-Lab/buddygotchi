import Foundation
import LinkKit

/// Which body Boop talks to: its board, or the simulator, the board's
/// firmware on this Mac in a window of the app's own (simulator/README.md),
/// in the debug and internal builds.
public enum DeviceChoice: String, Sendable {
    case board
    case simulator
}

/// The device link when there's a choice of device: the board's transport
/// until the simulator is chosen, then the one the app's window gives.
/// Nothing above it knows which it is: changing over is a drop and a new
/// connection, as a board swapped for another is. The simulator, chosen,
/// stays Boop's body until the board is chosen again (the app keeps the
/// choice from launch to launch), and the board isn't looked for meanwhile.
public final class DeviceChooser: Transport, @unchecked Sendable {
    private let board: Transport
    /// The simulator's link, made each time it's chosen.
    private let makeSimulator: @Sendable () -> Transport
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var simulator: Transport?
    private var onLine: (@Sendable (String) -> Void)?
    private var onConnection: (@Sendable (Bool) -> Void)?
    private var onChoice: (@Sendable (DeviceChoice) -> Void)?
    private var started = false
    /// Goes up at every change, so a transport no longer chosen is no longer heard.
    private var turn = 0
    private var up = false

    /// `simulator` makes the simulator's link each time it's chosen.
    public init(board: Transport, simulator: @escaping @Sendable () -> Transport, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.board = board
        makeSimulator = simulator
        self.log = log
    }

    public var choice: DeviceChoice { lock.withLock { simulator == nil ? .board : .simulator } }
    private var current: Transport { lock.withLock { simulator ?? board } }

    public var name: String { current.name }
    public var trouble: TransportTrouble? { current.trouble }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        let turn = lock.withLock {
            self.onLine = onLine
            self.onConnection = onConnection
            started = true
            return self.turn
        }
        start(current, turn)
    }

    public func send(_ line: String) { current.send(line) }
    public func reconnect() { current.reconnect() }

    public func stop() {
        let was = lock.withLock {
            started = false
            turn += 1
            return simulator ?? board
        }
        was.stop()
    }

    /// Hears each change of device.
    public func onChoice(_ hear: @escaping @Sendable (DeviceChoice) -> Void) { lock.withLock { onChoice = hear } }

    /// Changes over to the board or the simulator. What the device was
    /// playing ends as a drop ends it.
    public func choose(_ choice: DeviceChoice) {
        guard choice != self.choice else { return }
        let (was, now, turn, started, wasUp, dropped, hear) = lock.withLock {
            let was: Transport = simulator ?? board
            simulator = choice == .simulator ? makeSimulator() : nil
            self.turn += 1
            defer { up = false }
            return (was, simulator ?? board, self.turn, self.started, up, onConnection, onChoice)
        }
        log("device: now \(choice == .simulator ? "the simulator" : "the board") (\(now.name))")
        hear?(choice)
        guard started else { return }
        was.stop()
        if wasUp { dropped?(false) }
        start(now, turn)
    }

    private func start(_ transport: Transport, _ turn: Int) {
        transport.start(onLine: { [weak self] line in
            guard let self, let heard = self.lock.withLock({ self.turn == turn ? self.onLine : nil }) else { return }
            heard(line)
        }, onConnection: { [weak self] up in
            guard let self, let changed = self.lock.withLock({ () -> (@Sendable (Bool) -> Void)? in
                guard self.turn == turn else { return nil }
                self.up = up
                return self.onConnection
            }) else { return }
            changed(up)
        })
    }
}
