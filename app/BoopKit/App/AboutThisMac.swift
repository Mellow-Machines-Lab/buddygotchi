import Darwin
import Foundation

/// The app and the Mac it runs on, for the top of `boop.log` and a bug
/// report's `about.json`.
public enum AboutThisMac {
    /// Whether `bundle` is an app's, `Boop.app` as people install it, and
    /// not the folder of a bare binary (`make run`): what's missing from
    /// one is fixed by installing again, not by building.
    public static func isApp(_ bundle: URL = Bundle.main.bundleURL) -> Bool { bundle.pathExtension == "app" }

    /// The app bundle's build number (`make bundle` stamps it), or `dev`
    /// for a bare binary.
    public static var build: String {
        guard isApp() else { return "dev" }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    /// `15.4.1`.
    public static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// The Mac's model identifier, `Mac16,10`.
    public static var model: String { sysctl("hw.model") ?? "unknown" }

    /// What this process runs as: `arm64`, or `x86_64` (Intel, or Rosetta).
    public static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// `Boop 1.0.0 (21) on macOS 15.4.1, Mac16,10, arm64`.
    public static var line: String { "Boop \(BoopVersion.current) (\(build)) on macOS \(macOS), \(model), \(arch)" }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
}
