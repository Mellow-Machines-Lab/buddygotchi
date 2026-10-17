@preconcurrency import CoreBluetooth
import Foundation

/// The device over Bluetooth: a Nordic UART central (SPEC.md §8). Finds a
/// device advertising as `<prefix>-XXXX`, or only the one named `only`
/// when it's given, connects without pairing,
/// subscribes to TX, writes lines to RX in pieces no bigger than the link
/// allows, and reconnects after a drop: 1 s later, doubling to 5 s while
/// attempts keep failing.
///
/// Only the app itself creates this. A process started from an agent's or
/// a test's shell must never start it: macOS kills a process that touches
/// Bluetooth without the right to, which is why tests use `SocketTransport`.
public final class BLETransport: NSObject, Transport, @unchecked Sendable {
    public static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Mac → device.
    public static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Device → Mac.
    public static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    /// An attempt that can't carry lines this long after it started is
    /// given up and tried again.
    public static let connectTimeout: TimeInterval = 10

    /// The device's own name is in this transport's log lines.
    public let name = "ble"
    /// Devices advertise as `<prefix>-XXXX` (SPEC.md §8): `Lamp` finds `Lamp-54fe`.
    public let prefix: String
    /// The one device to take, by its exact advertised name (`Lamp-54fe`),
    /// or nil for the first whose name has the prefix. Several transports,
    /// each with its own device, can run side by side this way: none takes
    /// another's.
    public let only: String?
    /// The app's name in the words `trouble` says: `Lamp isn't allowed to use Bluetooth.`
    public let appName: String
    /// Read from any thread, so it's kept apart from `peripheral`.
    public var trouble: String? { troubleLock.withLock { stateTrouble } }
    let troubleLock = NSLock()
    var stateTrouble: String?

    let log: @Sendable (String) -> Void
    // Touched only on `queue`, which is also CoreBluetooth's delegate queue.
    let queue = DispatchQueue(label: "linkkit.ble", qos: .userInitiated)
    var central: CBCentralManager?
    /// The device being connected to, or connected. Callbacks about any
    /// other peripheral are left over from an attempt already given up.
    var peripheral: CBPeripheral?
    var rxCharacteristic: CBCharacteristic?
    /// Subscribed to TX, so lines flow both ways.
    var up = false
    var framer = LineFramer()
    /// Lines waiting for CoreBluetooth to take them.
    var outbox = BLEOutbox()
    var onLine: (@Sendable (String) -> Void)?
    var onConnection: (@Sendable (Bool) -> Void)?
    var running = false
    var backoff = ReconnectBackoff()
    /// Bumps on every attempt and drop, so an old attempt's timeout does nothing.
    var attempt = 0

    /// `prefix` is what the device's advertised name starts with, before
    /// its `-`; `only`, when given, is the one device's whole name; `appName`
    /// defaults to the prefix.
    public init(prefix: String, only: String? = nil, appName: String? = nil,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.prefix = prefix
        self.only = only
        self.appName = appName ?? prefix
        self.log = log
        super.init()
    }

    /// Whether an advertised name is the device this transport takes: the
    /// one named `only` when it's set, else any with the prefix.
    func isOurs(_ name: String?) -> Bool {
        guard let name else { return false }
        if let only { return name == only }
        return name.hasPrefix(prefix + "-")
    }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            self.onLine = onLine
            self.onConnection = onConnection
            running = true
            if central == nil { central = CBCentralManager(delegate: self, queue: queue) } else { findDevice() }
        }
    }

    /// Writes without response are dropped once CoreBluetooth's queue is
    /// full, which would splice lines on the device, so each piece waits
    /// until `canSendWriteWithoutResponse`, and `peripheralIsReady` sends
    /// the rest. No line is dropped on the way: a link too stuck to take
    /// them is given up instead (`BLEOutbox.stuck`), so the link fails the
    /// `do`s waiting on it at once rather than a minute later.
    public func send(_ line: String) {
        queue.async { [self] in
            guard up, let peripheral, rxCharacteristic != nil, peripheral.state == .connected else { return }
            outbox.add(line, size: peripheral.maximumWriteValueLength(for: .withoutResponse))
            drain()
            if outbox.stuck {
                log("ble: \(outbox.bytes) bytes waiting to go out, reconnecting")
                giveUp(peripheral)
            }
        }
    }

    func drain() {
        guard up, let peripheral, let rxCharacteristic else { return }
        while peripheral.canSendWriteWithoutResponse, let chunk = outbox.next() {
            peripheral.writeValue(chunk, for: rxCharacteristic, type: .withoutResponse)
        }
    }

    public func reconnect() {
        queue.async { [self] in
            guard running else { return }
            log("ble: reconnecting on request")
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            forget()
            backoff.reset()
            findDevice()
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        }
    }

    /// Takes over a link macOS already holds, or scans. A device that's
    /// still connected to the Mac isn't advertising, so after the app is
    /// killed and restarted a scan alone would never find it.
    func findDevice() {
        guard running, let central, central.state == .poweredOn, peripheral == nil else { return }
        let held = central.retrieveConnectedPeripherals(withServices: [Self.service])
        if let device = held.first(where: { isOurs($0.name) }) {
            log("ble: taking over macOS's connection to \(device.name ?? only ?? prefix)")
            connect(device)
        } else {
            central.scanForPeripherals(withServices: [Self.service], options: nil)
        }
    }

    func connect(_ device: CBPeripheral) {
        central?.stopScan()
        peripheral = device
        device.delegate = self
        central?.connect(device, options: nil)
        attempt += 1
        let this = attempt
        queue.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, attempt == this, peripheral === device, !up else { return }
            log("ble: \(device.name ?? only ?? prefix) not ready after \(Int(Self.connectTimeout)) s, trying again")
            giveUp(device)
        }
    }

    /// Ends this attempt or connection and looks again after the backoff.
    func giveUp(_ device: CBPeripheral) {
        central?.cancelPeripheralConnection(device)
        dropped()
    }

    func dropped() {
        forget()
        queue.asyncAfter(deadline: .now() + backoff.next()) { [weak self] in self?.findDevice() }
    }
}

extension BLETransport {
    /// Lets go of the device, so callbacks about it are ignored from now on.
    func forget() {
        let wasUp = up
        peripheral = nil
        rxCharacteristic = nil
        up = false
        framer = LineFramer()
        outbox = BLEOutbox()
        attempt += 1
        if wasUp { onConnection?(false) }
    }
}

/// What waits to go out over Bluetooth, as whole lines cut into write-sized
/// pieces, in order. A line that has started goes out whole. A newer
/// `state` takes the place of one still waiting, since only the latest
/// matters; every other line goes out, since the host waits for each `do`'s
/// `ended` (SPEC.md §8). With the states merged only `do`s pile up, so past
/// `limit` bytes the link is stuck, and the transport gives it up.
struct BLEOutbox {
    static let limit = 4096
    private var lines: [(state: Bool, chunks: [Data])] = []
    /// Pieces of the first line already written.
    private var sent = 0

    var bytes: Int { lines.reduce(0) { $0 + $1.chunks.reduce(0) { $0 + $1.count } } }
    /// More than `limit` bytes wait: the link isn't taking them.
    var stuck: Bool { bytes > Self.limit }

    mutating func add(_ line: String, size: Int) {
        let state = line.hasPrefix(#"{"t":"state""#)
        let chunks = LineFramer.chunks(line, size: size)
        if state, let i = lines.indices.last(where: { lines[$0].state && ($0 > 0 || sent == 0) }) {
            lines[i].chunks = chunks
        } else {
            lines.append((state, chunks))
        }
    }

    /// The next piece to write, or nil when nothing waits.
    mutating func next() -> Data? {
        guard let first = lines.first else { return nil }
        let chunk = first.chunks[sent]
        sent += 1
        if sent == first.chunks.count {
            lines.removeFirst()
            sent = 0
        }
        return chunk
    }
}

/// How long the Bluetooth link waits before looking for the device again:
/// 1 s after a drop, doubling up to 5 s while attempts keep failing, and
/// back to 1 s once a connection works.
struct ReconnectBackoff {
    static let first: TimeInterval = 1
    static let longest: TimeInterval = 5
    private(set) var delay = first

    mutating func next() -> TimeInterval {
        defer { delay = min(Self.longest, delay * 2) }
        return delay
    }

    mutating func reset() { delay = Self.first }
}

extension BLETransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("ble: Bluetooth \(Self.words(central.state))")
        troubleLock.withLock { stateTrouble = Self.trouble(central.state, appName: appName) }
        if central.state == .poweredOn {
            findDevice()
        } else if peripheral != nil {
            dropped()
        }
    }

    /// What the app says while Bluetooth can't be used: off, not allowed
    /// at the first launch's prompt or later, or missing. Nil while it's on
    /// or on its way.
    public static func trouble(_ state: CBManagerState, appName: String) -> String? {
        switch state {
        case .poweredOff: "Bluetooth is off. Turn it on in Control Center."
        case .unauthorized: "\(appName) isn't allowed to use Bluetooth. Allow it in System Settings → Privacy & Security → Bluetooth."
        case .unsupported: "This Mac has no Bluetooth that \(appName) can use."
        default: nil
        }
    }

    static func words(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "not allowed"
        case .unsupported: "not supported"
        case .resetting: "resetting"
        case .unknown: "state unknown"
        @unknown default: "state \(state.rawValue)"
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard isOurs(name), self.peripheral == nil else { return }
        log("ble: found \(name)")
        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        peripheral.discoverServices([Self.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        log("ble: connect failed: \(error.map { "\($0)" } ?? "no reason given")")
        dropped()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        guard peripheral === self.peripheral else { return }
        log("ble: disconnected" + (error.map { ": \($0)" } ?? ""))
        dropped()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            log("ble: no UART service" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        peripheral.discoverCharacteristics([Self.rx, Self.tx], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        let characteristics = service.characteristics ?? []
        guard error == nil, let rx = characteristics.first(where: { $0.uuid == Self.rx }),
              let tx = characteristics.first(where: { $0.uuid == Self.tx }) else {
            log("ble: no RX and TX" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        rxCharacteristic = rx
        peripheral.setNotifyValue(true, for: tx)
    }

    /// The link is up once the device's lines can reach the Mac.
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == Self.tx, !up else { return }
        guard error == nil, characteristic.isNotifying else {
            log("ble: can't subscribe to TX" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        up = true
        backoff.reset()
        log("ble: connected to \(peripheral.name ?? only ?? prefix)")
        onConnection?(true)
    }

    /// A reflashed device whose GATT table changed: macOS's cached copy is
    /// stale, so start over.
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === self.peripheral, invalidatedServices.contains(where: { $0.uuid == Self.service }) else { return }
        log("ble: the device's services changed, reconnecting")
        giveUp(peripheral)
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        drain()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == Self.tx, let value = characteristic.value else { return }
        for line in framer.push(value) { onLine?(line) }
    }
}
