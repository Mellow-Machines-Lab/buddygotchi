import Foundation
import MellowHarness

/// Boop's memory, run on the pipeline: two readers of the transcript, fed
/// every event as it's logged with the line Jev read for it, the day's
/// (`MemoryReader`: CONTEXT's Today row and the XP caps) and the dream's
/// (`DreamReader`: everything since the last dream). A dream updates the
/// memory from everything since its checkpoint: it makes the dream (tags
/// and a sentence, for the telling), runs the dream's write to
/// `memory.md`, and starts the span again. It dreams when you press `d`
/// on the dashboard, once a sleep when Boop has been asleep with no agent
/// working for `settleMs`,
/// and at once when it hasn't in `fallbackMs`; each only with something
/// new, and one at a time. The dream is kept in the key-value store
/// (`dream.last`) and logged as a `dream` event at the next tick, for the
/// view to tell; the line that tells it marks it told. Attached where the
/// pipeline is made, so the app, `--headless` and the evals all have it.
/// Touched on the harness's queue, but for the write, which asks the
/// writer off it and lands its edits back on it (`queue`).
public final class Memory: @unchecked Sendable {
    public let store: KeyValueStore
    /// `wishDone`'s answers: every `state` asks, and they change only here.
    private var wishesDone: [String: Bool] = [:]
    public let reader: MemoryReader
    public let runner: Checkpointed<MemoryReader>
    public let dreamReader: DreamReader
    public let dreams: Checkpointed<DreamReader>
    /// Whether Boop is asleep and no agent works: the pipeline's, once
    /// attached (`Pipeline.asleepAndIdle`).
    var asleep: () -> Bool = { false }
    /// Whether you're away from the Mac: the pipeline's view's, once
    /// attached. A sleep you're away for is one sleep, an agent's turn in
    /// it or not.
    var away: () -> Bool = { false }
    /// A dream is being made: its write hasn't landed yet.
    public private(set) var dreaming = false
    /// Boop dreamed in this sleep already; and since when it has been
    /// asleep and idle, nil while it isn't.
    var dreamtThisSleep = false
    var sleepingSince: Int64?
    /// How long Boop is asleep and idle before it dreams by itself: a
    /// coffee break isn't a sleep.
    public static let settleMs: Int64 = 20 * 60_000
    /// A span this long with something new dreams at once, whatever Boop
    /// is doing: two days.
    public static let fallbackMs: Int64 = 48 * 3_600_000
    weak var harness: Harness?
    let note: (String) -> Void
    let time: LocalTime
    /// The dream's writer, the memory files and the queue the dream's edits
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
        dreamReader = DreamReader(time: time)
        dreams = Checkpointed(dreamReader, store: store, time: time, note: note)
        // A memory from before dreams had spans starts its span where the
        // day's reader is, so the first dream covers what comes after.
        if dreams.state == nil, let day = runner.day { dreams.begin(at: runner.seq, day: day, state: DreamReader.Span()) }
    }

    /// What the dream's writer was asked, and its reply.
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

    /// Asks the writer to edit the written memory for `dream` from its
    /// span's `tallies` and journal: once, and once more with a quarter of
    /// RECENT left out if it didn't fit. Nil with no writer.
    public func ask(_ dream: Dream, tallies: MemoryReader.Tallies) async -> Night? {
        guard let writer, let files else { return nil }
        let day = dream.day, range = dream.range ?? "\(dream.weekday) \(day)"
        let journal = tallies.journal.map { (at: $0.at, line: $0.line) }
        let certain = MemoryRequest.certain(tallies, range: range)
        let started = Date()
        var request = MemoryRequest.make(memory: files.written(), certain: certain, journal: journal)
        var reply = await writer.write(request)
        if reply == .tooLong {
            request = MemoryRequest.make(memory: files.written(), certain: certain, journal: journal, lines: request.lines * 3 / 4)
            reply = await writer.write(request)
        }
        return Night(day: day, request: request, reply: reply, words: MemoryRequest.words(in: journal),
                     source: MemoryRequest.source(certain: certain, journal: journal),
                     fallback: "\(Self.weekdays(range)): \(dream.sentence).", ms: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// A span's dates as Recently's line names them, its day said already:
    /// "Friday", "Thursday to Saturday".
    static func weekdays(_ range: String) -> String {
        range.components(separatedBy: " to ").map { String($0.split(separator: " ").first ?? "") }.joined(separator: " to ")
    }

    /// The dream's edits to `memory`, checked, and what they'd make of it:
    /// nothing written. Nil when the writer gave nothing.
    public static func edits(_ night: Night, to memory: WrittenMemory) -> (next: WrittenMemory, report: MemoryEdits.Report)? {
        guard case .reply(let text) = night.reply else { return nil }
        var (next, report) = MemoryEdits.apply(text, to: memory, numbered: night.request.numbered, day: night.day,
                                               words: night.words, source: night.source)
        if !report.day {
            next.recently.removeAll { $0.day == night.day }
            next.recently = Array(([WrittenMemory.Day(day: night.day, text: night.fallback)] + next.recently)
                .sorted { $0.day > $1.day }.prefix(WrittenMemory.recentDays))
        }
        return (next, report)
    }

    /// The dream's edits, checked and applied to `memory.md` as it is now
    /// (a hand edit meanwhile counts), with a `memory` event saying what
    /// changed and what was refused, never the text.
    @discardableResult
    public func apply(_ night: Night) -> MemoryEdits.Report? {
        guard let files else { return nil }
        guard let (next, report) = Self.edits(night, to: files.written()) else {
            note("memory: the dream's write for \(night.day) gave nothing (\(night.reply))")
            return nil
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
        note("memory: the dream's write for \(night.day): \(report.updated.count) updated, \(report.added.count) added, "
             + "\(report.dropped.count) dropped, \(report.aged.count) aged, \(report.refused.count) refused")
        return report
    }

    /// Feeds it every event the pipeline logs, and ticks it before every
    /// input, on the harness's wall clock; asks the pipeline whether Boop
    /// is asleep and no agent works.
    public func attach(to pipeline: Pipeline) {
        let h = pipeline.harness
        harness = h
        asleep = { [weak pipeline, weak h] in
            guard let pipeline, let h else { return false }
            return pipeline.asleepAndIdle(at: h.clock.now())
        }
        away = { [weak pipeline] in pipeline?.view.away ?? false }
        pipeline.beforeInput.append { [weak self, weak h] _ in
            guard let self, let h else { return }
            tick(wall: h.clock.wall())
        }
        h.on("*") { [weak self, weak h] e in self?.heard(e, line: h?.line(e.seq)) }
    }

    /// The newest dream, told or not.
    public var dream: Dream? { Dream.last(in: store) }
    /// Today's tallies so far.
    public var today: MemoryReader.Tallies? { runner.state }
    /// Everything since the last dream.
    public var span: DreamReader.Span? { dreams.state }

    func heard(_ e: Event, line: Line?) {
        if let day = line?.facts["dream_day"]?.string { told(day) }
        recordAsk(e)
        recordWish(e)
        runner.feed(e, line: line)
        dreams.feed(e, line: line)
    }

    // MARK: The wish's "done once"

    /// Whether you've met a wish of `kind` once (`wish.<kind>`). Until
    /// then it shows how. For you, not for one buddy: you know how now.
    public func wishDone(_ kind: Core.WishKind) -> Bool {
        if let known = wishesDone[kind.rawValue] { return known }
        let done = store.string("wish.\(kind.rawValue)") != nil
        wishesDone[kind.rawValue] = done
        return done
    }

    /// Keeps a wish met (the `wish_end` event).
    func recordWish(_ e: Event) {
        guard e.type == .wish, e.phase == .end, e.specificType == Core.WishEnd.met.rawValue, let kind = e["kind"]?.string else { return }
        do {
            try store.set(["wish.\(kind)": time.boopDay(e.at)])
            wishesDone[kind] = true
        } catch { note("memory: can't keep the wish: \(error)") }
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
        if e.kind == Event.did, e.action == MomentOutput.outputName, let id = e["ask"]?.string {
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

    /// Opens the next day once the last is over; dreams when it should;
    /// and logs a dream not yet logged.
    public func tick(wall: Int64) {
        runner.tick(wall: wall)
        dreams.tick(wall: wall)
        let now = harness?.clock.now() ?? wall
        let sleeping = asleep()
        if !sleeping, !away() { dreamtThisSleep = false }
        sleepingSince = sleeping ? sleepingSince ?? now : nil
        if let span, span.new, !dreaming {
            if now - (span.since ?? now) >= Self.fallbackMs {
                dream(at: now, why: "it hasn't dreamed in two days")
            } else if let since = sleepingSince, now - since >= Self.settleMs, !dreamtThisSleep {
                dream(at: now, why: "asleep, and no agent works")
            }
        }
        guard var dream = dream, !dream.told, !dream.logged, let h = harness else { return }
        dream.logged = true
        save(dream)
        h.emit(dream.event(at: h.clock.now()))
        note("memory: dreamed about \(dream.about ?? dream.weekday) (\(dream.day)): \(dream.sentence)")
    }

    /// Dreams now, debug mode's `dream_now` (the dashboard's `d`): as Boop
    /// would asleep, logged at the next tick, its write landing when the
    /// writer answers. Nothing new since the last dream, or a dream still
    /// being made, and it doesn't.
    public func dreamNow(at now: Int64) {
        guard !dreaming else { return note("memory: a dream is being made already") }
        guard span?.new == true else { return note("memory: nothing new since the last dream") }
        dream(at: now, why: "asked")
    }

    /// The dream of everything since the last: kept, to be logged and
    /// told; the span started again (the checkpoint moved); then the
    /// write, live, off the harness's queue. One at a time.
    func dream(at now: Int64, why: String) {
        guard let span, let dream = dreamReader.dream(span, now: now) else { return }
        save(dream)
        dreamtThisSleep = true
        dreams.update { $0 = DreamReader.Span(since: now) }
        note("memory: dreaming (\(why)) about \(dream.about ?? dream.weekday)")
        guard let queue else { return }
        dreaming = true
        Task { [weak self] in
            let night = await self?.ask(dream, tallies: span.tallies)
            queue.async {
                if let night { self?.apply(night) }
                self?.dreaming = false
            }
        }
    }

    /// What dreaming now would do, with nothing committed: the dream, and
    /// the writer's edits to `memory.md` as it is (kept, updated, added,
    /// dropped, refused) with the file before and after. The checkpoint,
    /// the key-value store, `memory.md` and the transcript are left as
    /// they are. Without a writer, the dream alone.
    public struct Preview: Sendable {
        public var dream: Dream?
        public var report: MemoryEdits.Report?
        public var before: String?
        public var after: String?
    }

    public func preview(at now: Int64) async -> Preview {
        guard let span, let dream = dreamReader.dream(span, now: now) else { return Preview() }
        guard let files, let night = await ask(dream, tallies: span.tallies) else { return Preview(dream: dream) }
        let before = files.written()
        guard let (after, report) = Self.edits(night, to: before) else { return Preview(dream: dream, before: before.markdown) }
        return Preview(dream: dream, report: report, before: before.markdown, after: after.markdown)
    }

    /// The events the files hold after either checkpoint, read as they
    /// came: a launch after a crash or a quit catches up through the same
    /// readers, with no lines.
    public func catchUp(_ events: [Event]) {
        for e in events {
            recordWish(e)
            if e.seq > runner.seq { runner.feed(e, line: nil, live: false) }
            if e.seq > dreams.seq { dreams.feed(e, line: nil, live: false) }
        }
    }

    /// Where the readers read from, the earlier of the two checkpoints.
    public var seq: Int { min(runner.seq, dreams.seq) }
    public var from: String { [runner.day, dreams.day].compactMap { $0 }.min() ?? "" }

    /// The transcript starting again, its files gone: both checkpoints
    /// follow it back.
    public func follow(transcriptAt seq: Int) {
        runner.follow(transcriptAt: seq)
        dreams.follow(transcriptAt: seq)
    }

    /// At launch: a dream not yet told whose event has left the log is
    /// logged again at the next tick, so a weekend away still hears it.
    public func relog(unlessIn log: LogView) {
        guard var dream = dream, !dream.told, dream.logged,
              !log.events.contains(where: { $0.type == .dream && $0["day"]?.string == dream.day }) else { return }
        dream.logged = false
        save(dream)
    }

    /// Empties the journal since the last dream: what the person asked
    /// Boop to forget never reaches the dream's write.
    public func forgetJournal() { dreams.update { $0.tallies.journal = [] } }

    func told(_ day: String) {
        guard var dream = dream, dream.day == day, !dream.told else { return }
        dream.told = true
        save(dream)
    }

    func save(_ dream: Dream) {
        do { try dream.save(in: store) } catch { note("memory: can't keep the dream: \(error)") }
    }
}
