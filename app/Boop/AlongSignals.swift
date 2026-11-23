import AppKit
import BoopKit
import CoreAudio
import CoreGraphics
import CoreMediaIO

/// The Mac's facts for what Boop notices of you at the Mac (`Along`), read
/// on the runtime's queue every hands tick. None asks for a permission and
/// none is content: idle times, the pointer's place, which apps play or
/// record sound and whether a camera runs, the frontmost app's bundle id
/// and the pasteboard's change count, never what it holds.
///
/// The pointer, the keys, the scroll and the pasteboard are read every
/// tick (4 a second); sound, the mic and the camera once a second, which
/// they debounce over seconds anyway, so the Mac's devices aren't asked
/// more often.
final class AlongSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var front: String?
    private var token: NSObjectProtocol?
    /// The slow facts as last read, and when.
    private var slow = Along.Facts()
    private var slowAt: Date?
    static let slowEvery: TimeInterval = 1

    /// Keeps the frontmost app's bundle id as it changes, on the main
    /// thread, where NSWorkspace says so.
    @MainActor func start() {
        front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.lock.withLock { self?.front = app?.bundleIdentifier }
        }
    }

    /// The facts now, but the key and input idle times (`PresenceSignals`).
    func read() -> Along.Facts {
        let front = lock.withLock { self.front }
        if slowAt.map({ -$0.timeIntervalSinceNow >= Self.slowEvery }) ?? true {
            slowAt = Date()
            slow = Self.readSlow(front: front)
        }
        var f = slow
        f.front = front
        f.scrollIdleMs = Self.idleMs(.scrollWheel)
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
        f.copies = NSPasteboard.general.changeCount
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
    static func readSlow(front: String?) -> Along.Facts {
        var f = Along.Facts()
        f.camera = cameraRunning()
        // Which app plays or records sound is Core Audio's process objects,
        // from macOS 14.2; on 14.0 and 14.1 there are none, so no sound or
        // mic facts at all there (the camera still counts for a call).
        if #available(macOS 14.2, *) {
            for p in AudioProcess.all() where p.pid != getpid() {
                if p.output {
                    if p.belongs(to: front) { f.frontSound = true } else { f.otherSound = true }
                }
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

    /// Whether this is the frontmost app's sound: its own process, one of
    /// its helpers (Chrome's play from `com.google.Chrome.helper`), or for
    /// Safari, WebKit's (Safari plays from `com.apple.WebKit.GPU`).
    func belongs(to front: String?) -> Bool {
        guard let front, let bundle else { return false }
        if bundle == front || bundle.hasPrefix(front + ".") { return true }
        return front == "com.apple.Safari" && bundle.hasPrefix("com.apple.WebKit.")
    }

    static func all() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var out: UInt32 = 0, inp: UInt32 = 0, pid: pid_t = 0
            guard get(id, kAudioProcessPropertyIsRunningOutput, &out), get(id, kAudioProcessPropertyIsRunningInput, &inp),
                  out != 0 || inp != 0 else { return nil }
            _ = get(id, kAudioProcessPropertyPID, &pid)
            var bundle: Unmanaged<CFString>?
            _ = get(id, kAudioProcessPropertyBundleID, &bundle)
            let name = bundle?.takeRetainedValue() as String?
            return AudioProcess(pid: pid, bundle: name?.isEmpty == true ? nil : name, output: out != 0, input: inp != 0)
        }
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
