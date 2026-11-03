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
/// view to tell; the moment that tells it, once it has played, marks it
/// told. Attached where the
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
    /// How many times you've asked Boop to forget: a write or a line asked
    /// for before the last one doesn't land.
    private var forgets = 0
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

    /// The span's digest, with a writer to read it.
    func digest(of dream: Dream, tallies: MemoryReader.Tallies) -> DayDigest? {
        guard writer != nil else { return nil }
        let day = dream.covers ?? dream.day
        return DayDigest.from(day: day, weekday: time.weekday(of: day), tallies: tallies, first: tallies.firstYours.map(time.clock) ?? "",
                              last: tallies.lastYours.map(time.clock) ?? "",
                              journal: tallies.journal.map { (at: $0.at, line: $0.line) })
    }

    /// Keeps the span's digest (`memory-days.json`).
    func keepDigest(of dream: Dream, tallies: MemoryReader.Tallies) {
        guard let files, let digest = digest(of: dream, tallies: tallies) else { return }
        keep(files.days().keeping(digest, added: []))
    }

    /// Asks the writer to edit the written memory for `dream` from its
    /// span's `tallies` and journal. `kept` when the span's digest is in the
    /// file already, as a dream's is; a preview's isn't, and stays out. Nil
    /// with no writer.
    public func ask(_ dream: Dream, tallies: MemoryReader.Tallies, kept: Bool = false) async -> Night? {
        guard let writer, let files, let tonight = digest(of: dream, tallies: tallies) else { return nil }
        let range = dream.range ?? "\(dream.weekday) \(dream.day)"
        let journal = tallies.journal.map { (at: $0.at, line: $0.line) }
        let certain = MemoryRequest.certain(tallies, range: range)
        let started = Date()
        let memory = files.written(), days = files.days()
        let digests = kept ? days.digests : days.keeping(tonight, added: []).digests
        var input = MemoryPipeline.Input(memory: memory, digests: digests, certain: certain, journal: journal, day: tonight.day, weekday: tonight.weekday)
        input.forgotten = days.added.filter { text in !memory.notes.contains { $0.text == text } }
        let request = MemoryRequest(input)
        let reply = await writer.write(request)
        return Night(day: tonight.day, request: request, reply: reply, words: MemoryRequest.words(in: journal),
                     source: input.source,
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
        let before = files.written()
        guard let (next, report) = Self.edits(night, to: before) else {
            note("memory: the dream's write for \(night.day) gave nothing (\(night.reply))")
            return nil
        }
        do { try files.keep(next, day: night.day) } catch { note("memory: can't write memory.md: \(error)") }
        keep(files.days().following(report, from: before, to: next))
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
        // The moment that tells the dream played through.
        if e.kind == Event.ended, e.action == MomentOutput.outputName, e["outcome"]?.string == "done", let h = harness,
           let about = e.about.flatMap({ h.log.event($0) })?.about, let day = h.line(about)?.facts["dream_day"]?.string {
            told(day)
        }
        recordAsk(e)
        recordWish(e)
        recordFelt(e)
        // The dream's first: reading `e` can earn a stage, whose `grew` is
        // logged and heard inside the day's read, with a later seq.
        dreams.feed(e, line: line)
        runner.feed(e, line: line)
    }

    // MARK: Memory you feel

    /// A note Boop may bring up: its line in the pet's voice, and the note.
    public struct Felt: Equatable, Sendable {
        public var line: String, note: String
        public init(line: String, note: String) {
            self.line = line
            self.note = note
        }
    }

    /// The most notes given a line a dream: each is a call.
    public static let signsADream = 4
    /// The most offered at an idle check-in; a line shown isn't offered again
    /// for this many days.
    public static let feltOffered = 3, feltAgainDays = 14

    /// The notes with no line yet, and the lines kept without those of notes
    /// gone. Nothing asked here: a note whose line the checks refused is kept
    /// as "", and one the model didn't answer for isn't kept at all.
    func missingSigns() -> [String] {
        guard let files else { return [] }
        var days = files.days()
        let notes = files.written().notes.map(\.text)
        let kept = days.signs.filter { notes.contains($0.key) }
        if kept != days.signs {
            days.signs = kept
            keep(days)
        }
        return Array(notes.filter { kept[$0] == nil }.prefix(Self.signsADream))
    }

    func keep(_ days: MemoryStore.Days) {
        do { try files?.keep(days) } catch { note("memory: can't write the digests: \(error)") }
    }

    func keep(signs: [String: String]) {
        guard let files, !signs.isEmpty else { return }
        var days = files.days()
        days.signs.merge(signs) { _, new in new }
        keep(days)
    }

    /// At the dream's write, each new note gets its line, off the queue:
    /// one call a note, on this Mac.
    func writeSigns(queue: DispatchQueue) {
        guard let writer else { return }
        let notes = missingSigns()
        guard !notes.isEmpty else { return }
        let asked = forgets
        Task { [weak self] in
            var signs: [String: String] = [:]
            for text in notes {
                switch await writer.sign(for: text) {
                case .line(let line): signs[text] = line
                case .refused: signs[text] = ""
                case .noAnswer: break
                }
            }
            queue.async {
                guard let self, asked == self.forgets else { return }
                self.keep(signs: signs)
            }
        }
    }

    /// What Boop may bring up at `ms`: at most `feltOffered` lines that fit
    /// `longest` characters (`MemoryPipeline.signRoom`), those shown longest
    /// ago first, none shown in `feltAgainDays`; none at all if one was shown
    /// today.
    public func felt(at ms: Int64, longest: Int = MemoryPipeline.signMax) -> [Felt] {
        guard let files else { return [] }
        let signs = files.days().signs
        guard !signs.isEmpty else { return [] }
        let shown = feltShown(), today = time.boopDay(ms)
        guard !shown.values.contains(today), let now = LocalTime.dayNumber(today) else { return [] }
        func age(_ line: String) -> Int { shown[line].flatMap(LocalTime.dayNumber).map { now - $0 } ?? .max }
        return files.written().notes.compactMap { n in
            signs[n.text].flatMap { $0.isEmpty || $0.count > longest || age($0) < Self.feltAgainDays ? nil : Felt(line: $0, note: n.text) }
        }.sorted { age($0.line) > age($1.line) }.prefix(Self.feltOffered).map { $0 }
    }

    /// When each line was last shown (`felt`, in the key-value store).
    func feltShown() -> [String: String] {
        store.string("felt").flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
    }

    /// Keeps a line shown once its moment has played through, as a dream
    /// is told: the react output's `did` names the line, and a moment cut
    /// short leaves it to offer again.
    func recordFelt(_ e: Event) {
        guard e.kind == Event.ended, e.action == MomentOutput.outputName, e["outcome"]?.string == "done",
              let line = e.about.flatMap({ harness?.log.event($0) })?["felt"]?.string else { return }
        keepShown(line, at: e.at)
    }

    func keepShown(_ line: String, at ms: Int64) {
        var shown = feltShown()
        shown[line] = time.boopDay(ms)
        guard let data = try? JSONEncoder().encode(shown) else { return }
        do { try store.set(["felt": String(decoding: data, as: UTF8.self)]) } catch { note("memory: can't keep the line shown: \(error)") }
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

    /// The dream of everything since the last: kept with its digest, to be
    /// logged and told; the span started again (the checkpoint moved); then
    /// the write, live, off the harness's queue. One at a time.
    func dream(at now: Int64, why: String) {
        guard let span, let dream = dreamReader.dream(span, now: now) else { return }
        save(dream)
        keepDigest(of: dream, tallies: span.tallies)
        dreamtThisSleep = true
        dreams.update { $0 = DreamReader.Span(since: now) }
        note("memory: dreaming (\(why)) about \(dream.about ?? dream.weekday)")
        guard let queue else { return }
        dreaming = true
        let asked = forgets
        Task { [weak self] in
            let night = await self?.ask(dream, tallies: span.tallies, kept: true)
            queue.async {
                guard let self else { return }
                if let night {
                    if asked == self.forgets { self.apply(night) } else { self.note("memory: you asked Boop to forget, so the dream's write for \(night.day) is dropped") }
                }
                self.dreaming = false
                self.writeSigns(queue: queue)
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

    /// Forgets what's behind the notes you asked Boop to forget, so the next
    /// dream's write can't make them again: the span's journal and counts,
    /// the digests', and the line shown for each note gone. What it counts
    /// of its care stays (`MemoryReader.Tallies.forgotten`). Call it with
    /// `memory.md` already as you left it.
    public func forgetAboutYou() {
        forgets += 1
        dreams.update { $0.tallies = $0.tallies.forgotten }
        guard let files else { return }
        do { try files.forgetLearned() } catch { note("memory: can't write the digests: \(error)") }
        let lines = Set(files.days().signs.values)
        let shown = feltShown().filter { lines.contains($0.key) }
        if let data = try? JSONEncoder().encode(shown) {
            do { try store.set(["felt": String(decoding: data, as: UTF8.self)]) } catch { note("memory: can't keep the line shown: \(error)") }
        }
    }

    func told(_ day: String) {
        guard var dream = dream, dream.day == day, !dream.told else { return }
        dream.told = true
        save(dream)
    }

    func save(_ dream: Dream) {
        do { try dream.save(in: store) } catch { note("memory: can't keep the dream: \(error)") }
    }
}
