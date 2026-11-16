import AppKit
import BoopKit
import CoreAudio
import CoreGraphics
import CoreMediaIO

/// The Mac's facts for what Boop notices of you at the Mac (`Along`), read
/// on the runtime's queue every hands tick. None asks for a permission and
/// none is content: idle times, the pointer's place, whether the default
/// output or input device or a camera is running somewhere, the frontmost
/// app's bundle id and the pasteboard's change count, never what it holds.
final class AlongSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var front: String?
    private var token: NSObjectProtocol?

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
    func read() -> Along.Reading {
        var r = Along.Reading()
        r.scrollIdleMs = Self.idleMs(.scrollWheel)
        r.clickIdleMs = min(Self.idleMs(.leftMouseDown), Self.idleMs(.rightMouseDown))
        // CoreGraphics' global coordinates, y down, as the anchor keeps them.
        if let p = CGEvent(source: nil)?.location {
            r.pointerX = p.x
            r.pointerY = p.y
            var display = CGDirectDisplayID(0), count: UInt32 = 0
            if CGGetDisplaysWithPoint(p, 1, &display, &count) == .success, count > 0 {
                let b = CGDisplayBounds(display)
                r.display = Anchor.Rect(x: b.minX, y: b.minY, width: b.width, height: b.height)
            }
        }
        r.sound = Self.running(kAudioHardwarePropertyDefaultOutputDevice)
        r.mic = Self.running(kAudioHardwarePropertyDefaultInputDevice)
        r.camera = Self.cameraRunning()
        r.front = lock.withLock { front }
        r.copies = NSPasteboard.general.changeCount
        return r
    }

    static func idleMs(_ type: CGEventType) -> Int64 {
        Int64(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type) * 1000)
    }

    /// Whether the default device of `which` (output or input) is running
    /// for any app.
    static func running(_ which: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: which, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var on = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &on) == noErr else { return false }
        return on != 0
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
