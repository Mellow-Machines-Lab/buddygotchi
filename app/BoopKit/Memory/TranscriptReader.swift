import Foundation
import MellowHarness

/// A reader of the transcript that remembers where it stopped: it goes
/// through the events in order, keeps a little state, and does its work
/// when Boop's day ends. Every memory is one; `Checkpointed` runs it, so a
/// memory has no cursor, catch-up or crash handling of its own.
public protocol TranscriptReader: AnyObject {
    associatedtype State: Codable
    /// Its checkpoint's key: `reader.<name>`.
    var name: String { get }
    /// The state Boop's day `day` starts with. `carry` is the day before's,
    /// for what runs across 5:00.
    func open(day: String, carry: State?) -> State
    /// Reads one event; true when it changed the state. `line` is what Jev
    /// read for it, nil when the event is read back from the files.
    func read(_ e: Event, line: Line?, into state: inout State) -> Bool
    /// Boop's day `day` is over. Called twice for one day, it does the
    /// same: it writes its own keys, the same values each time. `live` is
    /// false while catching up from the files.
    func close(day: String, state: State, live: Bool)
}

/// Runs a `TranscriptReader`: its checkpoint (the last event read, the
/// Boop day open, its state) as one row in the key-value store,
/// `reader.<name>`, saved after each read that changed the state and after
/// each close. An event at or before the checkpoint is skipped, so a
/// replay reads nothing twice. A crash between a close and its save
/// closes the same day again, which a reader's close allows: no outbox, no
/// queue, as Boop is one process on one Mac.
public final class Checkpointed<R: TranscriptReader> {
    struct Checkpoint: Codable {
        var seq: Int
        var day: String
        var state: R.State
    }

    public let reader: R
    let store: KeyValueStore
    let time: LocalTime
    let note: (String) -> Void
    private(set) var checkpoint: Checkpoint?

    var key: String { "reader.\(reader.name)" }

    public init(_ reader: R, store: KeyValueStore, time: LocalTime, note: @escaping (String) -> Void = { _ in }) {
        self.reader = reader
        self.store = store
        self.time = time
        self.note = note
        if let text = store.string("reader.\(reader.name)") {
            do { checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(text.utf8)) } catch {
                note("memory: \(reader.name)'s checkpoint doesn't read (\(error)); it starts again")
            }
        }
    }

    /// The `seq` of the last event read; 0 before any.
    public var seq: Int { checkpoint?.seq ?? 0 }
    /// The Boop day open, and its state so far.
    public var day: String? { checkpoint?.day }
    public var state: R.State? { checkpoint?.state }

    /// Reads `e`, closing the open day first when `e` is of a later one.
    public func feed(_ e: Event, line: Line?, live: Bool = true) {
        if let c = checkpoint, e.seq <= c.seq { return }
        let day = time.boopDay(e.at)
        var c = checkpoint ?? Checkpoint(seq: 0, day: day, state: reader.open(day: day, carry: nil))
        var changed = checkpoint == nil
        if day > c.day {
            c = closed(c, to: day, live: live)
            changed = true
        }
        if reader.read(e, line: line, into: &c.state) { changed = true }
        c.seq = e.seq
        checkpoint = c
        if changed { save() }
    }

    /// Closes the open day once the wall clock has passed its end.
    public func tick(wall: Int64) {
        guard let c = checkpoint else { return }
        let day = time.boopDay(wall)
        guard day > c.day else { return }
        checkpoint = closed(c, to: day, live: true)
        save()
    }

    /// Closes the open day now, as 5:00 would, and opens the same day
    /// afresh, its carry kept: debug mode's `close_day`. The day closes
    /// again at 5:00, where a reader that writes once a day (the dream)
    /// keeps what it wrote now.
    public func closeNow() {
        guard let c = checkpoint else { return }
        checkpoint = closed(c, to: c.day, live: true)
        save()
    }

    /// Changes the open day's state, and saves it.
    public func update(_ change: (inout R.State) -> Void) {
        guard var c = checkpoint else { return }
        change(&c.state)
        checkpoint = c
        save()
    }

    /// The transcript starting again, its files gone: the checkpoint
    /// follows it back, so nothing new is skipped.
    public func follow(transcriptAt seq: Int) {
        guard var c = checkpoint, seq < c.seq else { return }
        note("memory: the transcript starts again at \(seq), past \(c.seq); reading from there")
        c.seq = seq
        checkpoint = c
        save()
    }

    func closed(_ c: Checkpoint, to day: String, live: Bool) -> Checkpoint {
        reader.close(day: c.day, state: c.state, live: live)
        return Checkpoint(seq: c.seq, day: day, state: reader.open(day: day, carry: c.state))
    }

    func save() {
        guard let checkpoint, let data = try? JSONEncoder().encode(checkpoint) else { return }
        do { try store.set([key: String(decoding: data, as: UTF8.self)]) } catch {
            note("memory: can't save \(reader.name)'s checkpoint: \(error)")
        }
    }
}
