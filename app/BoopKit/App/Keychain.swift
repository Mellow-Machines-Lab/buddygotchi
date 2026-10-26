import Foundation

/// Jev's API key, kept in the login Keychain and nowhere else.
///
/// Boop reads and writes the entry through Apple's `/usr/bin/security`, not
/// the Security framework. The Keychain ties an entry to the program that
/// made it, and without an Apple-issued certificate it knows Boop only by
/// the exact build, so every rebuild asked for the key again. `security`
/// stays the same from build to build. The catch is that any program
/// running as the owner can read the entry that way without a prompt.
/// Both calls can block while macOS asks for access,
/// so they never run on the main thread or on the runtime's `home` queue.
public enum Keychain {
    static let service = "com.boopcomputer.boop"

    /// The entry's account for the Boop on `stateDir`: `jev`, the everyday
    /// Boop's, or a copy's own on another folder (`make dev`), named
    /// as its hook socket's listing is (`AppSettings.copyName`), so a copy
    /// never reads or replaces the everyday key.
    public static func account(for stateDir: URL, home: String = NSHomeDirectory()) -> String {
        AppSettings.isEveryday(stateDir, home: home) ? "jev" : AppSettings.copyName(stateDir)
    }

    public static func jevKey(account: String, security: SecurityTool = .system) -> String? {
        let found = security.run(["find-generic-password", "-s", service, "-a", account, "-w"], nil)
        guard found.status == 0 else { return nil }
        let key = found.output.trimmingCharacters(in: .newlines)
        return key.isEmpty ? nil : key
    }

    /// A key as pasted, without the spaces and newlines a copy picks up
    /// at either end, which Jev would refuse.
    public static func cleaned(_ key: String?) -> String {
        (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the entry, or removes it when `key` is nil or blank. The key
    /// reaches `security` hex-encoded on its stdin, never in its arguments,
    /// which any process can see. True when the Keychain now holds `key`,
    /// `cleaned`; when it doesn't, the key it held before is put back.
    @discardableResult
    public static func setJevKey(_ key: String?, account: String, security: SecurityTool = .system) -> Bool {
        let key = cleaned(key)
        let old = key.isEmpty ? nil : jevKey(account: account, security: security)
        _ = security.run(["delete-generic-password", "-s", service, "-a", account], nil)
        guard !key.isEmpty else { return true }
        add(key, account: account, security: security)
        // Read it back rather than trust the exit status of `security -i`.
        if jevKey(account: account, security: security) == key { return true }
        if let old { add(old, account: account, security: security) }
        return false
    }

    private static func add(_ key: String, account: String, security: SecurityTool) {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        _ = security.run(["-i"], "add-generic-password -s \(service) -a \(account) -X \(hex)\n")
    }
}

/// Runs `/usr/bin/security` with these arguments and this stdin, and
/// returns its exit status and what it printed. Tests pass their own.
public struct SecurityTool: Sendable {
    var run: @Sendable (_ arguments: [String], _ input: String?) -> (status: Int32, output: String)

    public static let system = SecurityTool { arguments, input in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdin = Pipe(), stdout = Pipe()
        // Into the pipe before `security` starts: a few hundred bytes fit
        // its buffer, and nothing is written after it could have exited.
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}
