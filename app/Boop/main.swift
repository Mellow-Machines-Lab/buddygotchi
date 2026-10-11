import AppKit
import BoopKit
import Foundation
import MellowHarness
import LinkKit

// The Boop app. With no arguments it's the menu-bar app on Bluetooth.
// `--headless` runs the same runtime with no UI and no Bluetooth, for tests
// and agents (VERIFICATION.md L4).

let usage = """
    usage: Boop [--state-dir DIR] [--link ble|usb:SOCKET|none] [--debug]
               The menu-bar app. The owner runs this; it uses Bluetooth by default. With a --state-dir
               other than the everyday one it never installs or repairs the hooks in ~/.claude and
               ~/.codex: they keep reporting to the everyday app's socket, not this one.
           Boop --headless --state-dir DIR [--link usb:SOCKET|none] [--socket PATH] [--personality boop|chatter]
                [--brain jev|scripted] [--name NAME] [--nature sweet|cheeky] [--no-open] [--debug]
                [--demo FILE|pack [--record FILE]]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). --personality overrides the saved one for this run only.
               --brain jev (the default) asks Jev only when BOOP_JEV_KEY holds its key, since headless never
               reads the Keychain; without it Boop does only its rule reactions. --brain scripted answers
               every pass the same way without a network: an excited "Go", for pipeline checks.
               Stops cleanly on SIGINT or SIGTERM. {"dev":"advance","ms":N} on the socket moves the clock forward,
               and {"dev":"tap"} stands in for a tap on the board. A tap while something needs you opens that
               thread on this Mac; --no-open only logs where it would have opened.
               Every event goes to DIR/transcript/<date>.jsonl, read back at the next launch.
               --demo plays a demo script (pack: the character pack's own, demo/demo.jsonl) and stops when it's
               over; with a link it waits for the device first. It runs with no brain unless --brain says one:
               the script says how Boop reacts. --record writes every line the device was sent, with when and
               what was happening, for the simulator's page to play back.
           --debug prints everything to this terminal as it happens: each hook and the raw event Boop made
               of it, every line sent to the device, and every view event, pass (with Jev's whole state) and
               action. The events, view events and passes also go to DIR/debug.jsonl, started afresh each
               launch, with the lines sent to the device, status changes and the questions (boopdev watch
               and boopctl dash read it). The last 10 launches' files are kept as DIR/debug.1.jsonl (the latest) to
               debug.10.jsonl, and boopctl day sums them all up by the hour. Jev's state never reaches boop.log.
           Headless, or with --debug, the hook socket also takes {"dev":…} lines from boopctl dash: "answer"
               (a forced pass) and "mood"; and for push-to-talk with no mic, "listen" (the app's button,
               {"dev":"listen","on":true}) and "said" (what the mic heard, {"dev":"said","words":"…"}).
           Boop --snapshots DIR
               Renders the popover's panes and the menu-bar icons to PNGs from fixtures, then exits.
               No runtime, no Bluetooth.
           A flag the chosen way doesn't take stops Boop with this usage, before anything starts.
    (boop \(BoopVersion.current))
    """

/// The character pack bundled with the app: the one `make build` staged
/// (characters/CHARACTER.md §2), which the bundle's `packs/chosen` names.
func bundledCharacter() -> CharacterPack {
    guard let packs = Bundle.module.url(forResource: "packs", withExtension: nil),
          let chosen = try? String(contentsOf: packs.appendingPathComponent("chosen"), encoding: .utf8) else {
        fail("the character pack is missing from the app: build it with make build, which stages it")
    }
    let url = packs.appendingPathComponent(chosen.trimmingCharacters(in: .whitespacesAndNewlines))
    do { return try CharacterPack(directory: url) } catch { fail("the app's character pack is broken: \(error)") }
}

/// The steering folder of the app's character pack.
func bundledSteering() -> Steering {
    let url = CharacterPack.active.directory.appendingPathComponent("steering")
    do { return try Steering(directory: url) } catch { fail("the app's steering folder is broken: \(error)") }
}

/// The runtime's options on `stateDir`: the device over `link`, the log in
/// `log`, in debug mode everything printed to the terminal, and with
/// `devLines` the dashboard's `{"dev":…}` lines taken. The menu-bar app and `--headless` both start from these.
func runtimeOptions(stateDir: URL, socketPath: String, link: LinkSetting, debug: Bool, devLines: Bool,
                    log: LogFile) -> Runtime.Options {
    let transport: Transport? = switch link {
    // The board over Bluetooth, or a simulator running on this Mac, when
    // Settings is told to use it.
    case .bluetooth: DeviceChooser(board: BLETransport(prefix: BoopDevice.blePrefix, log: { log.write($0) }),
                                   log: { log.write($0) })
    case .usb(let path): SocketTransport(path: path)
    case .none: nil
    }
    var options = Runtime.Options(stateDir: stateDir, socketPath: socketPath, link: transport, steering: bundledSteering())
    options.log = { log.write($0) }
    options.debug = debug
    options.debugPrint = { log.echo($0) }
    options.devLines = devLines
    return options
}

/// Appends to `DIR/boop.log`, and echoes to stderr when asked. `echo`
/// prints to stderr alone, for what must stay out of the file. One past
/// 5 MB is moved aside first (`BoopLog.rotate`).
final class LogFile: @unchecked Sendable {
    let url: URL
    let handle: FileHandle?
    let echo: Bool
    let lock = NSLock()
    let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(directory: URL, echo: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("boop.log")
        BoopLog.rotate(in: directory)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        self.echo = echo
    }

    func write(_ message: String) {
        lock.withLock {
            let line = stamped(message)
            // The throwing write: the old one raises an Objective-C exception
            // (a crash) on any error, such as a full disk.
            try? handle?.write(contentsOf: line)
            if echo { try? FileHandle.standardError.write(contentsOf: line) }
        }
    }

    func echo(_ message: String) {
        lock.withLock { try? FileHandle.standardError.write(contentsOf: stamped(message)) }
    }

    /// The message as a line, after the time. Only under `lock`.
    private func stamped(_ message: String) -> Data {
        Data((format.string(from: Date()) + " " + message + "\n").utf8)
    }
}

// The ways to run Boop and what each takes. Anything else stops with the
// usage: a mistyped flag would otherwise start the menu-bar app, which uses
// Bluetooth and repairs the real hooks.
let raw = Array(CommandLine.arguments.dropFirst())
let (launchHeadless, launchSnapshots) = (raw.contains("--headless"), raw.contains("--snapshots"))
let (launchOptions, launchFlags): (Set<String>, Set<String>) =
    launchHeadless ? (["--state-dir", "--link", "--socket", "--personality", "--brain", "--name", "--nature", "--demo", "--record"],
                      ["--headless", "--debug", "--no-open"])
    : launchSnapshots ? (["--snapshots"], [])
    : (["--state-dir", "--link"], ["--debug"])
let args = Arguments.parse(raw, options: launchOptions, flags: launchFlags, command: "boop", usage: usage)
CharacterPack.use(bundledCharacter())
if launchHeadless { Headless.run(args) }
if launchSnapshots { MainActor.assumeIsolated { Snapshots.run(args) } }
MenuBarApp.run(args)
