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
                [--brain jev|scripted|none] [--labeler apple|none] [--name NAME] [--nature sweet|cheeky] [--no-open] [--debug]
                [--demo FILE|pack|pack:NAME [--live] [--record FILE]] [--buddies PLACE:PACK[:AGENT[:NAME]],… [--links LINK,…]]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). --personality overrides the saved one for this run only.
               --brain jev (the default) asks Jev only when BOOP_JEV_KEY holds its key, since headless never
               reads the Keychain; without it Boop does only its rule reactions. --brain scripted answers
               every pass the same way without a network: an excited "Go", for pipeline checks. --brain none
               asks no brain at all, even with a key: only the rules, and dev lines' answers. --labeler apple
               reads your prompts with Apple Intelligence, as the app does; none (the default) only counts them.
               --buddies runs several buddies side by side, each with its place (left, right), its character pack,
               the agent it watches first and its own name; --links gives each its own link, in order (usb:SOCKET
               or none). A demo whose header names buddies runs them without --buddies. With several, a {"dev":…}
               line takes "buddy": PLACE for the one it's for.
               Stops cleanly on SIGINT or SIGTERM. {"dev":"advance","ms":N} on the socket moves the clock forward,
               and {"dev":"tap"} stands in for a tap on the board. A tap while something needs you opens that
               thread on this Mac; --no-open only logs where it would have opened.
               Every event goes to DIR/transcript/<date>.jsonl, read back at the next launch.
               --demo plays a demo script (pack: the character pack's own, demo/demo.jsonl; pack:NAME its
               demo/NAME.jsonl) and stops when it's over; with a link it waits for the device first. It runs with
               no brain unless --brain says one: the script says how Boop reacts. With --live a real agent plays
               the script's agent, its hooks coming to the socket, and the rest keeps to its pace; the line due
               now is in DIR/demo-cursor. --record writes every line the device was sent, with when and what was
               happening, for the simulator's page to play back.
           --debug prints everything to this terminal as it happens: each hook and the raw event Boop made
               of it, every line sent to the device, and every view event, pass (with Jev's whole state) and
               action. The events, view events and passes also go to DIR/debug.jsonl, started afresh each
               launch, with the lines sent to the device, status changes and the questions (boopctl dash
               reads it). The last 10 launches' files are kept as DIR/debug.1.jsonl (the latest) to
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
/// (characters/CHARACTER.md §2), which the bundle's `packs/chosen` names
/// among every pack it holds. `BOOP_CHARACTER`, a pack's folder, comes
/// first, as for the tests and boopdev, so one build plays any pack's demo.
func bundledCharacter() -> CharacterPack {
    if let path = ProcessInfo.processInfo.environment["BOOP_CHARACTER"], !path.isEmpty {
        do { return try CharacterPack(directory: CharacterPack.staged(URL(fileURLWithPath: path).standardizedFileURL)) } catch { fail("BOOP_CHARACTER: \(error)") }
    }
    guard let packs = bundledPacks,
          let chosen = (try? String(contentsOf: packs.appendingPathComponent("chosen"), encoding: .utf8))?
              .trimmingCharacters(in: .whitespacesAndNewlines) else {
        fail("the character pack is missing from the app: build it with make build, or make bundle, which stage it")
    }
    do { return try CharacterPack(directory: packs.appendingPathComponent(chosen)) } catch { fail("the app's character pack is broken: \(error)") }
}

/// The folder of every character pack the app holds, for buddies that run
/// another pack. In `Boop.app` it's in Contents/Resources, where
/// `make bundle` puts it: SwiftPM's `Bundle.module` looks at the top of the
/// app, where code signing allows nothing, and when that fails falls back
/// to the build folder, which on the Mac that built it would quietly
/// work. A bare binary uses SwiftPM's resource bundle beside it.
let bundledPacks = Bundle.main.bundleURL.pathExtension == "app"
    ? Bundle.main.url(forResource: "packs", withExtension: nil)
    : Bundle.module.url(forResource: "packs", withExtension: nil)

/// The steering folder of a character pack, the app's by default.
func bundledSteering(_ pack: CharacterPack = .active) -> Steering {
    let url = pack.directory.appendingPathComponent("steering")
    do { return try Steering(directory: url, pack: pack) } catch { fail("\(pack.id)'s steering folder is broken: \(error)") }
}

/// The transport for `link`: over Bluetooth, the first board it finds, or
/// the one named `only`.
func transport(_ link: LinkSetting, only: String? = nil, log: LogFile) -> Transport? {
    switch link {
    case .bluetooth: BLETransport(prefix: BoopDevice.blePrefix, only: only, log: { log.write((only.map { "\($0): " } ?? "") + $0) })
    case .usb(let path): SocketTransport(path: path)
    case .none: nil
    }
}

/// The runtime's options on `stateDir`: the device over `link`, the log in
/// `log`, in debug mode everything printed to the terminal, and with
/// `devLines` the dashboard's `{"dev":…}` lines taken. The menu-bar app and `--headless` both start from these.
func runtimeOptions(stateDir: URL, socketPath: String, link: LinkSetting, debug: Bool, devLines: Bool,
                    log: LogFile, buddies: [BuddySetting] = [], links: [LinkSetting] = []) -> Runtime.Options {
    // The board over Bluetooth, or a simulator running on this Mac, when
    // Settings is told to use it. Over Bluetooth, the one Boop takes only
    // the board it remembered, and narrows to the first one it meets.
    let remembered = buddies.count > 1 ? nil : AppSettings.load(from: stateDir).board.flatMap(BoopDevice.advertised)
    let board = transport(link, only: remembered, log: log)
    var options = Runtime.Options(stateDir: stateDir, socketPath: socketPath,
                                  link: board.map { DeviceChooser(board: $0, log: { log.write($0) }) }, steering: bundledSteering())
    if let ble = board as? BLETransport, buddies.count <= 1 { options.chooseBoard = { ble.take(only: $0) } }
    // Several buddies: each its own board, over Bluetooth the one its
    // `board` names, else its own link in `links`, in order.
    if buddies.count > 1 {
        options.buddies = buddies.enumerated().map { i, setting in
            let buddy: Buddy
            do { buddy = try setting.buddy(bundled: bundledPacks, among: buddies) } catch { fail("buddy \(setting.place): \(error)") }
            let own = i < links.count ? links[i] : link == .bluetooth ? .bluetooth : .none
            return Runtime.BuddyOptions(buddy: buddy, link: transport(own, only: setting.board.flatMap(BoopDevice.advertised), log: log),
                                        steering: bundledSteering(buddy.pack))
        }
    }
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
        // What ran, at the top of each launch's lines.
        write("boop: " + AboutThisMac.line)
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
    launchHeadless ? (["--state-dir", "--link", "--socket", "--personality", "--brain", "--labeler", "--name", "--nature", "--demo", "--record",
                       "--buddies", "--links"],
                      ["--headless", "--debug", "--no-open", "--live"])
    : launchSnapshots ? (["--snapshots"], [])
    : (["--state-dir", "--link"], ["--debug"])
let args = Arguments.parse(raw, options: launchOptions, flags: launchFlags, command: "boop", usage: usage)
CharacterPack.use(bundledCharacter())
if launchHeadless { Headless.run(args) }
if launchSnapshots { MainActor.assumeIsolated { Snapshots.run(args) } }
MenuBarApp.run(args)
