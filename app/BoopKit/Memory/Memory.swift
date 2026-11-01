import Foundation
import MellowHarness

/// Boop's memory, run on the pipeline: the readers of the transcript (in
/// v1 one, `MemoryReader`), fed every event as it's logged with the line
/// Jev read for it, and ticked at the start of every input, so a day that's
/// over closes before the event after it is read. The dream a close writes
/// is kept in the key-value store (`dream.last`) and logged as a `dream`
/// event at the next tick, for the view to tell; the line that tells it
/// marks it told. Attached where the pipeline is made, so the app,
/// `--headless` and the evals all have it. Touched on the harness's queue,
/// but for the night's write, which asks the writer off it and lands its
/// edits back on it (`queue`).
public final class Memory: @unchecked Sendable {
    public let store: KeyValueStore
    public let reader: MemoryReader
    public let runner: Checkpointed<MemoryReader>
    weak var harness: Harness?
    let note: (String) -> Void
    let time: LocalTime
    /// The night's writer, the memory files and the queue the night's edits
    /// land on (the harness's): with none, no written memory.
    let writer: MemoryWriter?
    let files: MemoryStore?
    let queue: DispatchQueue?

    public init(store: KeyValueStore, time: LocalTime, writer: MemoryWriter? = nil, files: MemoryStore? = nil,
                queue: DispatchQueue? = nil, note: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.note = note
        self.time = time
        self.writer = writer
        self.files = files
        self.queue = queue
        reader = MemoryReader(store: store, time: time)
        runner = Checkpointed(reader, store: store, time: time, note: note)
        reader.wrote = { [weak self] dream in self?.keep(dream) }
        reader.closed = { [weak self] day, tallies, live in
            guard live, let self, let queue = self.queue else { return }
            Task { [weak self] in
                guard let night = await self?.ask(day: day, tallies: tallies) else { return }
                queue.async { self?.apply(night) }
            }
        }
    }

    /// What the night's writer was asked, and its reply.
    public struct Night: Sendable {
        public var day: String
        public var request: MemoryRequest
        public var reply: MemoryWriterReply
        public var words: [String]
        /// CERTAIN and yesterday's lines, which every change must be tied to.
        public var source: String
        /// Recently's line when the writer gives none that passes: the
        /// dream's own sentence, which is always true.
        public var fallback: String
        public var ms: Int
    }

    /// Asks the writer to edit the written memory for the day `day` from
    /// its `tallies` and journal: once, and once more with a quarter of
    /// YESTERDAY left out if it didn't fit. Nil with no writer.
    public func ask(day: String, tallies: MemoryReader.Tallies) async -> Night? {
        guard let writer, let files else { return nil }
        let journal = tallies.journal.map { (at: $0.at, line: $0.line) }
        let certain = MemoryRequest.certain(tallies, day: day, weekday: time.weekday(of: day))
        let started = Date()
        var request = MemoryRequest.make(memory: files.written(), certain: certain, journal: journal)
        var reply = await writer.write(request)
        if reply == .tooLong {
            request = MemoryRequest.make(memory: files.written(), certain: certain, journal: journal, lines: request.lines * 3 / 4)
            reply = await writer.write(request)
        }
        return Night(day: day, request: request, reply: reply, words: MemoryRequest.words(in: journal),
                     source: MemoryRequest.source(certain: certain, journal: journal),
                     fallback: "\(time.weekday(of: day)): \(MemoryReader.sentence(tallies)).", ms: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// The night's edits, checked and applied to `memory.md` as it is now
    /// (a hand edit meanwhile counts), with a `memory` event saying what
    /// changed and what was refused, never the text.
    @discardableResult
    public func apply(_ night: Night) -> MemoryEdits.Report? {
        guard let files else { return nil }
        guard case .reply(let text) = night.reply else {
            note("memory: the night's write for \(night.day) gave nothing (\(night.reply))")
            return nil
        }
        var (next, report) = MemoryEdits.apply(text, to: files.written(), numbered: night.request.numbered, day: night.day,
                                               words: night.words, source: night.source)
        if !report.day {
            next.recently.removeAll { $0.day == night.day }
            next.recently = Array(([WrittenMemory.Day(day: night.day, text: night.fallback)] + next.recently)
                .sorted { $0.day > $1.day }.prefix(WrittenMemory.recentDays))
        }
        do { try files.keep(next, day: night.day) } catch { note("memory: can't write memory.md: \(error)") }
        if let h = harness {
            func ids(_ xs: [Int]) -> JSONValue { .array(xs.map { .string("m\($0)") }) }
            h.emit(Event(at: h.clock.now(), source: .boop, type: .memory, specificType: "night",
                         data: ["day": .string(night.day), "kept": ids(report.kept), "updated": ids(report.updated),
                                "added": ids(report.added), "dropped": ids(report.dropped), "aged": ids(report.aged),
                                "day_line": .bool(report.day), "ms": .int(Int64(night.ms)),
                                "refused": .array(report.refused.map { .object(["line": .string($0.line), "why": .string($0.why)]) })]))
        }
        note("memory: the night's write for \(night.day): \(report.updated.count) updated, \(report.added.count) added, "
             + "\(report.dropped.count) dropped, \(report.aged.count) aged, \(report.refused.count) refused")
        return report
    }

    /// Feeds it every event the pipeline logs, and ticks it before every
    /// input, on the harness's wall clock.
    public func attach(to pipeline: Pipeline) {
        let h = pipeline.harness
        harness = h
        pipeline.beforeInput.append { [weak self, weak h] _ in
            guard let self, let h else { return }
            tick(wall: h.clock.wall())
        }
        h.on("*") { [weak self, weak h] e in self?.heard(e, line: h?.line(e.seq)) }
    }

    /// The newest dream, told or not.
    public var dream: Dream? { Dream.last(in: store) }
    /// Today's tallies and journal so far.
    public var today: MemoryReader.Tallies? { runner.state }

    func heard(_ e: Event, line: Line?) {
        if let day = line?.facts["dream_day"]?.string { told(day) }
        recordAsk(e)
        runner.feed(e, line: line)
    }

    // MARK: The ask record

    /// What's kept of the question `id` asked (`ask.<id>`), or nil.
    public func askRecord(_ id: String) -> Asks.Record? {
        store.string("ask.\(id)").flatMap { try? JSONDecoder().decode(Asks.Record.self, from: Data($0.utf8)) }
    }

    /// Every question's record, by its id.
    public func askRecords() -> [String: Asks.Record] {
        store.prefixed("ask.").reduce(into: [:]) { out, row in
            if let r = try? JSONDecoder().decode(Asks.Record.self, from: Data(row.value.utf8)) { out[String(row.key.dropFirst(4))] = r }
        }
    }

    /// The answers kept as tags today, for every sign's lines.
    public func answerTags(at ms: Int64) -> [String] { Asks.answerTags(askRecords(), today: time.boopDay(ms)) }

    /// Keeps a question asked (the react output's `did` names it) and its
    /// end (the `ask` event), one row a question.
    func recordAsk(_ e: Event) {
        var record: Asks.Record?
        if e.kind == Event.did, e.action == ReactOutput.outputName, let id = e["ask"]?.string {
            record = Asks.Record(asked: time.boopDay(e.at), keeps: e["keeps"]?.bool ?? false)
            save(record!, id)
        } else if e.type == .ask, let id = e["q"]?.string, var r = askRecord(id) {
            if e.specificType == Asks.ignored { r.ignored = true } else { r.answer = e["answer"]?.string }
            save(r, id)
        }
    }

    func save(_ record: Asks.Record, _ id: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        do { try store.set(["ask.\(id)": String(decoding: data, as: UTF8.self)]) } catch { note("memory: can't keep the ask: \(error)") }
    }

    /// Closes the day once it's over, and logs a dream not yet logged.
    public func tick(wall: Int64) {
        runner.tick(wall: wall)
        guard var dream = dream, !dream.told, !dream.logged, let h = harness else { return }
        dream.logged = true
        save(dream)
        h.emit(dream.event(at: h.clock.now()))
        note("memory: dreamed about \(dream.weekday) (\(dream.day)): \(dream.sentence)")
    }

    /// Closes Boop's day now, as 5:00 would (`Checkpointed.closeNow`): the
    /// dream, logged at once, then the night's write, which lands when
    /// the writer answers. Debug mode's `close_day`, so memory can be
    /// watched in seconds. A day nobody was in has no dream, and a day
    /// dreamed of already keeps its dream.
    public func closeNow(wall: Int64) {
        guard let t = today, let day = runner.day else { return note("memory: no day open to close") }
        if t.yours == 0 { note("memory: nobody was there on \(day), so no dream") }
        if dream?.day == day { note("memory: \(day) is dreamed of already, so no new dream") }
        runner.closeNow()
        tick(wall: wall)
    }

    /// The events the files hold after the checkpoint, read as the day
    /// they came: a launch after a crash or a quit catches up through the
    /// same reader, with no lines. A day closed on the way writes its dream
    /// but logs none: only the newest is told.
    public func catchUp(_ events: [Event]) {
        for e in events where e.seq > runner.seq { runner.feed(e, line: nil, live: false) }
    }

    /// At launch: a dream not yet told whose event has left the log is
    /// logged again at the next tick, so a weekend away still hears it.
    public func relog(unlessIn log: LogView) {
        guard var dream = dream, !dream.told, dream.logged,
              !log.events.contains(where: { $0.type == .dream && $0["day"]?.string == dream.day }) else { return }
        dream.logged = false
        save(dream)
    }

    /// Empties today's journal: what the person asked Boop to forget
    /// never reaches the night's write.
    public func forgetJournal() { runner.update { $0.journal = [] } }

    func keep(_ dream: Dream) { save(dream) }

    func told(_ day: String) {
        guard var dream = dream, dream.day == day, !dream.told else { return }
        dream.told = true
        save(dream)
    }

    func save(_ dream: Dream) {
        do { try dream.save(in: store) } catch { note("memory: can't keep the dream: \(error)") }
    }
}
