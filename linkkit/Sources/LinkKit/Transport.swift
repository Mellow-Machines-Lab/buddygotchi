import Foundation

/// One way to reach the device: `BLETransport` or `SocketTransport` (a USB
/// bridge). Both carry the same lines (SPEC.md §8), so nothing above this
/// knows which it is. An app can write its own, as tests do.
public protocol Transport: AnyObject, Sendable {
    /// For logs and bug reports: `ble`, or `usb:<bridge socket>`.
    var name: String { get }
    /// Why it can't look for the device at all (Bluetooth is off), or nil.
    /// Read from any thread.
    var trouble: TransportTrouble? { get }
    /// `onLine` gets each complete line from the device, and `onConnection`
    /// each change of connection, both on the transport's own thread: the
    /// owner hops to its queue before handing them to `DeviceLink`.
    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void)
    /// Sends one line (without its newline). Dropped when not connected:
    /// the next `state` catches the device up.
    func send(_ line: String)
    /// Drops the connection or attempt in progress and looks for the
    /// device again at once (a settings screen's Reconnect).
    func reconnect()
    func stop()
}

extension Transport {
    public var trouble: TransportTrouble? { nil }
}

/// Why a transport can't look for the device: its cause, for an app to
/// act on (open the right settings), and the words to show for it.
public struct TransportTrouble: Equatable, Sendable {
    public enum Cause: Equatable, Sendable {
        /// The radio is off.
        case off
        /// The app isn't allowed to use it.
        case notAllowed
        /// The computer has none the app can use.
        case unsupported
    }

    public var cause: Cause
    /// In plain words, with what to do: `Bluetooth is off. Turn it on in
    /// Control Center.`
    public var words: String

    public init(_ cause: Cause, _ words: String) {
        self.cause = cause
        self.words = words
    }
}
