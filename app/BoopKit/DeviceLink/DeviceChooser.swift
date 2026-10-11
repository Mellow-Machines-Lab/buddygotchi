import Darwin
import Foundation
import LinkKit

/// Which body Boop talks to: its board, or the simulator, a board in a
/// browser on this Mac (simulator/README.md).
public enum DeviceChoice: String, Sendable {
    case board
    case simulator
}

/// The device link when there's a choice of device: the board's transport
/// until the simulator is chosen, then the simulator's, over its USB
/// cable. Nothing above it knows which it is: changing over is a drop and
/// a new connection, as a board swapped for another is.
///
/// The simulator is a choice only while it's running, and the choice
/// isn't kept: when the simulator stops, Boop goes back to its board, and
/// the next launch starts with the board.
public final class DeviceChooser: Transport, @unchecked Sendable {
    /// Where a running simulator shares its board's USB, as a bridge
    /// shares a board's (simulator/web/serve.py).
    public static let simulatorSocket = "/tmp/boop-sim-usb.sock"

    private let board: Transport
    private let simulatorPath: String
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var simulator: SocketTransport?
    private var onLine: (@Sendable (String) -> Void)?
    private var onConnection: (@Sendable (Bool) -> Void)?
    private var started = false
    /// Goes up at every change, so a transport no longer chosen is no longer heard.
    private var turn = 0
    private var up = false

    public init(board: Transport, simulatorSocket: String = DeviceChooser.simulatorSocket,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.board = board
        simulatorPath = simulatorSocket
        self.log = log
    }

    public var choice: DeviceChoice { lock.withLock { simulator == nil ? .board : .simulator } }
    private var current: Transport { lock.withLock { simulator ?? board } }

    public var name: String { current.name }
    public var trouble: String? { current.trouble }

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

    /// Changes over to the board or the simulator. What the device was
    /// playing ends as a drop ends it.
    public func choose(_ choice: DeviceChoice) {
        guard choice != self.choice else { return }
        let (was, now, turn, started, wasUp, dropped) = lock.withLock {
            let was: Transport = simulator ?? board
            simulator = choice == .simulator ? SocketTransport(path: simulatorPath, name: "simulator") : nil
            self.turn += 1
            defer { up = false }
            return (was, simulator ?? board, self.turn, self.started, up, onConnection)
        }
        log("device: now \(choice == .simulator ? "the simulator" : "the board") (\(now.name))")
        guard started else { return }
        was.stop()
        if wasUp { dropped?(false) }
        start(now, turn)
    }

    /// Whether a simulator is running, and back to the board if the one
    /// chosen has stopped. The app asks every couple of seconds.
    public func simulatorIsThere() -> Bool {
        let chosen = lock.withLock { simulator != nil }
        let connected = lock.withLock { simulator != nil && up }
        let there = connected || DeviceChooser.answers(simulatorPath)
        if chosen, !there {
            log("device: the simulator stopped")
            choose(.board)
        }
        return there
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

    /// A socket of this user's own at `path` that takes a connection: one
    /// of another user's making is never Boop's simulator.
    static func answers(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
    }
}
