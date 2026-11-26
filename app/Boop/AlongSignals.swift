import AppKit
import BoopKit
import CoreAudio
import CoreGraphics
import CoreMediaIO

/// The Mac's facts for what Boop notices of you at the Mac (`Along`), read
/// on the runtime's queue every hands tick. None asks for a permission and
/// none is content: idle times, the pointer's place, the sign of the last
/// scroll, whether an app plays or records sound and whether a camera runs.
///
/// The pointer, the keys and the scroll are read every tick (4 a second);
/// sound, the mic and the camera once a second, which they debounce over
/// seconds anyway, so the Mac's devices aren't asked more often. Which
/// apps run sound at all is kept as Core Audio says it changes
/// (`AudioWatch`), so only those are asked.
final class AlongSignals: @unchecked Sendable {
    private let lock = NSLock()
    /// Which way the last scroll went, from a global monitor of scroll
    /// events, which needs no permission (only key events do): its sign
    /// alone is kept, never how far, where or in which app.
    private var scrollDown: Bool?
    private var scrollMonitor: Any?
    /// The slow facts as last read, and when.
    private var slow = Along.Facts()
    private var slowAt: Date?
    static let slowEvery: TimeInterval = 1
    /// An `AudioWatch`, from macOS 14.2.
    private let audio: AnyObject?

    init() {
        if #available(macOS 14.2, *) { audio = AudioWatch() } else { audio = nil }
    }

    /// Starts watching which way you scroll, on the main thread.
    @MainActor func start() {
        // AppKit's delta is the content's: below zero, the page moves on
        // toward its end, as the person sees it, natural scrolling or not.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let dy = event.scrollingDeltaY
            guard dy != 0 else { return }
            self?.lock.withLock { self?.scrollDown = dy < 0 }
        }
    }

    /// The facts now, but the key and input idle times (`PresenceSignals`).
    func read() -> Along.Facts {
        let scrollDown = lock.withLock { self.scrollDown }
        if slowAt.map({ -$0.timeIntervalSinceNow >= Self.slowEvery }) ?? true {
            slowAt = Date()
            slow = readSlow()
        }
        var f = slow
        f.scrollIdleMs = Self.idleMs(.scrollWheel)
        f.scrollDown = scrollDown
        f.clickIdleMs = min(Self.idleMs(.leftMouseDown), Self.idleMs(.rightMouseDown))
        // CoreGraphics' global coordinates, y down, as the anchor keeps them.
        if let p = CGEvent(source: nil)?.location {
            f.pointerX = p.x
            f.pointerY = p.y
            var display = CGDirectDisplayID(0), count: UInt32 = 0
            if CGGetDisplaysWithPoint(p, 1, &display, &count) == .success, count > 0 {
                f.display = Self.rect(CGDisplayBounds(display))
            }
        }
        return f
    }

    /// Every active display, for whether the anchor's is still there.
    static func displays() -> [Anchor.Rect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { rect(CGDisplayBounds($0)) }
    }

    static func rect(_ b: CGRect) -> Anchor.Rect { Anchor.Rect(x: b.minX, y: b.minY, width: b.width, height: b.height) }

    static func idleMs(_ type: CGEventType) -> Int64 {
        Int64(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type) * 1000)
    }

    /// Sound, the mic and the camera.
    func readSlow() -> Along.Facts {
        var f = Along.Facts()
        f.camera = Self.cameraRunning()
        // Which app plays or records sound is Core Audio's process objects,
        // from macOS 14.2; on 14.0 and 14.1 there are none, so no sound or
        // mic facts at all there (the camera still counts for a call).
        if #available(macOS 14.2, *), let audio = audio as? AudioWatch {
            for p in audio.processes() where p.pid != getpid() {
                if p.output { f.sound = true }
                if p.input, !AudioProcess.alwaysListening.contains(p.bundle ?? "") { f.otherInput = true }
            }
        }
        return f
    }

    /// Whether any camera is running for any app.
    static func cameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var on: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &on) == 0 && on != 0
        }
    }
}

/// One app as Core Audio sees it: whether it plays sound (output) or
/// records it (input) now, on any device. macOS 14.2 and later.
@available(macOS 14.2, *)
struct AudioProcess {
    let pid: pid_t
    let bundle: String?
    let output: Bool
    let input: Bool

    /// Apps that may keep the mic open with nothing on, which aren't a call:
    /// "Hey Siri" and its speech (CoreSpeech, assistantd, Siri) and Sound
    /// Recognition (accessibility's heard). None ran input on the owner's
    /// Mac when it was measured, idle (2026-11-16); they're here in case.
    static let alwaysListening: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.assistantd", "com.apple.Siri", "com.apple.accessibility.heard",
    ]

    static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Every process object Core Audio has now.
    static func objects() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}

/// Which apps run sound now, kept as Core Audio says it changes: asking
/// every process object each second was a message to coreaudiod for each,
/// about 7 ms a time, all day. Core Audio tells of a process object coming
/// and going, and of its sound starting and stopping (`IsRunning`), but
/// not of which way it runs (tried on macOS 27: `IsRunningOutput` never
/// tells), so only the processes running sound now are asked that.
@available(macOS 14.2, *)
final class AudioWatch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "boop.audio-watch")
    private let lock = NSLock()
    /// The process objects running sound now, and whose they are.
    private var running: [AudioObjectID: (pid: pid_t, bundle: String?)] = [:]
    /// Each process object's listener, to remove when it goes. On `queue`.
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    init() {
        queue.async { [self] in
            var address = AudioProcess.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioProcess.system, &address, queue) { [weak self] _, _ in self?.listChanged() }
            listChanged()
        }
    }

    /// The apps playing or recording sound now.
    func processes() -> [AudioProcess] {
        lock.withLock { running }.compactMap { id, who in
            var out: UInt32 = 0, inp: UInt32 = 0
            guard AudioProcess.get(id, kAudioProcessPropertyIsRunningOutput, &out),
                  AudioProcess.get(id, kAudioProcessPropertyIsRunningInput, &inp), out != 0 || inp != 0 else { return nil }
            return AudioProcess(pid: who.pid, bundle: who.bundle, output: out != 0, input: inp != 0)
        }
    }

    /// A process object came or went.
    private func listChanged() {
        let ids = Set(AudioProcess.objects())
        for (id, block) in listeners where !ids.contains(id) {
            var address = AudioProcess.address(kAudioProcessPropertyIsRunning)
            AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
            listeners[id] = nil
            lock.withLock { running[id] = nil }
        }
        for id in ids where listeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.runningChanged(id) }
            var address = AudioProcess.address(kAudioProcessPropertyIsRunning)
            guard AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr else { continue }
            listeners[id] = block
            runningChanged(id)
        }
    }

    /// A process's sound started or stopped.
    private func runningChanged(_ id: AudioObjectID) {
        var on: UInt32 = 0, pid: pid_t = 0
        var bundle: Unmanaged<CFString>?
        guard AudioProcess.get(id, kAudioProcessPropertyIsRunning, &on), on != 0 else {
            return lock.withLock { running[id] = nil }
        }
        _ = AudioProcess.get(id, kAudioProcessPropertyPID, &pid)
        _ = AudioProcess.get(id, kAudioProcessPropertyBundleID, &bundle)
        let name = bundle?.takeRetainedValue() as String?
        lock.withLock { running[id] = (pid, name?.isEmpty == true ? nil : name) }
    }
}
