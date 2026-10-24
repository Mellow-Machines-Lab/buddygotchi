import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Your prompt, read on the Mac (`PromptIntake`): scrubbed of secrets,
/// counted, labelled, and only its reading logged and heard by the brain.
final class PromptTests: XCTestCase {
    /// Every secret shape becomes `[secret]`, keeping the name it was given;
    /// ordinary words, paths and numbers stay.
    func testTheScrubberTakesSecretsOut() {
        let cases: [(String, String)] = [
            ("use sk-proj-8f2aQz91kLmN0pQrStUv to call it", "use [secret] to call it"),
            ("token ghp_abcdefghijklmnopqrstuvwxyz0123456789", "token [secret]"),
            ("aws AKIAIOSFODNN7EXAMPLE here", "aws [secret] here"),
            ("slack xoxb-1234567890-abcdefghij", "slack [secret]"),
            ("set API_KEY=abc123def456 and go", "set API_KEY=[secret] and go"),
            ("password: hunter2!", "password: [secret]"),
            (#"{"token": "abc.def"}"#, #"{"token": [secret]}"#),
            ("open https://me:pa55word@example.com/x", "open https://[secret]@example.com/x"),
            ("GET /cb?code=1&access_token=zzz&x=2", "GET /cb?code=1&access_token=[secret]&x=2"),
            ("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl ok", "jwt [secret] ok"),
            ("mail jo.smith+boop@example.co.uk now", "mail [secret] now"),
            ("hash 3f786850e387550fdab836ed7e6dc881de23001b done", "hash [secret] done"),
            ("-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----", "[secret]"),
        ]
        for (text, scrubbed) in cases { XCTAssertEqual(Scrubber.scrub(text), scrubbed, text) }
        let plain = "fix src/components/UploadButton.tsx: the 413 at 5MB, then run npm test (v1.4.0)"
        XCTAssertEqual(Scrubber.scrub(plain), plain, "paths, numbers and versions stay")
    }

    /// The scrubber against two corpora: every made-up secret in its real
    /// format is gone (`must-scrub.tsv`: the text, a tab, the secret), and
    /// ordinary prompt text, paths, versions, SQL, UUIDs and short hashes
    /// come through untouched (`must-keep.txt`).
    func testTheScrubbersCorpora() throws {
        let dir = CharacterPackTests.repo.appendingPathComponent("internal/app/Tests/Fixtures/scrubber")
        func lines(_ file: String) throws -> [String] {
            try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8).split(separator: "\n").map(String.init)
                .filter { !$0.hasPrefix("#") }
        }
        let secrets = try lines("must-scrub.tsv")
        XCTAssertGreaterThanOrEqual(secrets.count, 18)
        for line in secrets {
            let parts = line.split(separator: "\t").map(String.init)
            let text = parts[0].replacingOccurrences(of: "\\n", with: "\n"), scrubbed = Scrubber.scrub(text)
            XCTAssertFalse(scrubbed.contains(parts[1]), "kept a secret: \(scrubbed)")
            XCTAssertTrue(scrubbed.contains(Scrubber.secret), scrubbed)
        }
        for line in try lines("must-keep.txt") { XCTAssertEqual(Scrubber.scrub(line), line) }
    }

    /// Pins `AppleIntelligenceLabeler.timeout`'s race: the wait ends at the
    /// timeout even when the work ignores being cancelled, and the work is
    /// cancelled then.
    func testTheLabelerGivesUpAtItsTimeout() async {
        let started = ContinuousClock.now
        let cancelled = Lines()
        let labels = await AppleIntelligenceLabeler.within(.milliseconds(100)) {
            for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(100)) }  // carries on through cancelling
            if Task.isCancelled { cancelled.add("cancelled") }
            return PromptReading.Labels(kind: .fix)
        }
        XCTAssertNil(labels)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        XCTAssertEqual(AppleIntelligenceLabeler.timeout, .seconds(3))
        let quick = await AppleIntelligenceLabeler.within(.seconds(2)) { PromptReading.Labels(kind: .docs) }
        XCTAssertEqual(quick?.kind, .docs, "an answer in time is kept")
        eventually("the slow work was cancelled") { cancelled.all == ["cancelled"] }
    }

    /// The app's labeler is there on macOS 26 whether or not Apple
    /// Intelligence is on at launch, and asks at every prompt: while it's
    /// off, it labels nothing, at once.
    func testTheLabelerAsksAtEveryPrompt() async {
        if #available(macOS 26.0, *) {
            XCTAssertNotNil(AppleIntelligenceLabeler.onThisMac)
        } else {
            XCTAssertNil(AppleIntelligenceLabeler.onThisMac)
        }
        XCTAssertEqual(AppleIntelligenceLabeler.ifAvailable() != nil, AppleIntelligenceLabeler.isAvailable, "the tools' is there only while it's on")
        guard !AppleIntelligenceLabeler.isAvailable else { return }
        let labels = await AppleIntelligenceLabeler().label("fix the login redirect")
        XCTAssertNil(labels)
    }

    /// Pins `PromptReading.Length.bounds`: a few words under 25 characters,
    /// a sentence under 150, a paragraph under 600, an essay beyond.
    func testTheLengthBands() {
        for (n, length) in [(24, PromptReading.Length.words), (25, .sentence), (149, .sentence), (150, .paragraph),
                            (599, .paragraph), (600, .essay)] {
            XCTAssertEqual(PromptReading.Length(String(repeating: "a", count: n)), length, "\(n)")
        }
        XCTAssertEqual(PromptReading.Length("   continue \n"), .words, "the spaces around it don't count")
    }

    /// Counted with no model: the buddies' names said as words, in any
    /// case, and the tone the words plainly show; capitals are shouting.
    func testCountingSeesTheNameAndThePlainTone() {
        func read(_ text: String) -> PromptReading { PromptReading(counting: text, names: ["Pip", "Bo"]) }
        XCTAssertEqual(read("ok pip, watch this").named, ["Pip"], "the name as the buddy's called")
        XCTAssertEqual(read("pipe the logs to a file").named, [], "a word, not part of one")
        XCTAssertEqual(read("bo and PIP, both of you").named, ["Pip", "Bo"])
        XCTAssertEqual(read("WHY IS THE LOGIN STILL BROKEN").tone, .shouting)
        XCTAssertNil(read("fix the API").tone, "a capitalised word isn't shouting")
        XCTAssertEqual(read("please add a retry").tone, .polite)
        XCTAssertEqual(read("Thanks so much, add a retry").phrases, ["Thanks"], "the cue is a phrase, as you spelled it")
        XCTAssertEqual(read("WHY IS THE LOGIN STILL BROKEN").phrases, [], "shouting has no cue word")
        XCTAssertEqual(read("ultrathink: why is it stale").tone, .careful)
        XCTAssertEqual(read("just quickly fix it").tone, .rushed)
        XCTAssertEqual(read("lol ok try again 🙃").tone, .playful)
        XCTAssertNil(read("fix the login redirect").tone)
        XCTAssertNil(read("fix the login redirect").kind, "the kind needs a labeler")
    }

    /// A labeler's phrases are kept only if they really are in the prompt,
    /// fit a sign and hold no secret, at most three; its shouting is
    /// dropped, and a counted tone stands over its calm.
    func testALabelIsCheckedAgainstThePrompt() {
        let text = Scrubber.scrub("it's Still Broken again, key sk-proj-8f2aQz91kLmN0pQrStUv, please fix")
        var reading = PromptReading(counting: text, names: [])
        reading.label(.init(kind: .fix, tone: .calm, phrases: ["still broken", "ensure stability", "[secret]", "it's Still Broken again, key",
                                                              "again", "please", "fix"]), in: text)
        XCTAssertEqual(reading.kind, .fix)
        XCTAssertEqual(reading.phrases, ["Still Broken", "again", "please"], "its own spelling, three at most")
        XCTAssertEqual(reading.tone, .polite, "the counted tone over the labeler's calm")
        reading.label(.init(tone: .frustrated), in: text)
        XCTAssertEqual(reading.tone, .frustrated, "more than calm wins over a counted cue")
        var plain = PromptReading(counting: "ship it to prod", names: [])
        plain.label(.init(kind: .deploy, tone: .shouting), in: "ship it to prod")
        XCTAssertNil(plain.tone, "shouting is counted, never heard")
        XCTAssertEqual(PromptReading.maxPhrase, Signs.maxLength, "a phrase is what fits on a sign")
    }

    /// The counted cue is a phrase only while its tone is the reading's:
    /// a "please" under a frustrated tone the labeler heard would put
    /// "please :(" on a sign.
    func testACueStaysOnlyWithItsTone() {
        let text = "please, it's still broken"
        func labelled(_ labels: PromptReading.Labels) -> PromptReading {
            var reading = PromptReading(counting: text, names: [])
            XCTAssertEqual(reading.phrases, ["please"])
            reading.label(labels, in: text)
            return reading
        }
        let frustrated = labelled(.init(tone: .frustrated, phrases: ["still broken"]))
        XCTAssertEqual(frustrated.tone, .frustrated)
        XCTAssertEqual(frustrated.phrases, ["still broken"], "the labeler's tone won: no cue")
        XCTAssertEqual(labelled(.init(tone: .polite, phrases: ["still broken"])).phrases, ["still broken", "please"], "the same tone")
        XCTAssertEqual(labelled(.init(tone: .calm)).phrases, ["please"], "the counted tone stands over calm, and its cue")
        XCTAssertEqual(labelled(.init()).phrases, ["please"])
    }

    /// A phrase is kept as the board's sign font draws it
    /// (`Signs.drawn`): an accent typed as its own mark joins its letter,
    /// curly quotes and dashes go plain, and a phrase with anything else
    /// the board would draw as "?" is dropped, the cue's included.
    func testPhrasesAreWhatTheBoardDraws() {
        XCTAssertEqual(Signs.drawn("“so” — it’s fine…"), "\"so\" - it's fine...")
        XCTAssertEqual(Signs.drawn("cafe\u{301} · déjà vu"), "café · déjà vu")
        XCTAssertEqual(Signs.drawn("cafe\u{301}")?.utf8.count, 5, "é precomposed, which the board folds to e, not e and a ?")
        XCTAssertNil(Signs.drawn("还是不行"))
        XCTAssertNil(Signs.drawn("ok 🙃"))
        XCTAssertNil(Signs.drawn("q\u{301}"), "a mark with no letter to join")
        func read(_ text: String, _ phrases: [String]) -> [String] {
            var reading = PromptReading(counting: text, names: [])
            reading.label(.init(tone: .frustrated, phrases: phrases), in: text)
            return reading.phrases
        }
        XCTAssertEqual(read("登录还是不行, still broken", ["登录还是不行", "still broken"]), ["still broken"], "Chinese doesn't draw")
        XCTAssertEqual(read("it’s broken again", ["it’s broken"]), ["it's broken"], "a curly apostrophe")
        XCTAssertEqual(read("the cafe\u{301} page is broken", ["café page"]).map(\.utf8.count), [10], "a decomposed accent, precomposed")
        XCTAssertEqual(PromptReading(counting: "🙃 try again", names: []).tone, .playful)
        XCTAssertEqual(PromptReading(counting: "🙃 try again", names: []).phrases, [], "a cue the board can't draw is no phrase")
    }

    /// The reading round-trips through an event's facts, and the labeler's
    /// three lines parse, anything off a list dropped.
    func testTheReadingAsFactsAndTheLabelersReply() {
        let reading = PromptReading(length: .sentence, named: ["Pip"], kind: .cleanup, tone: .playful, phrases: ["bye bye"])
        XCTAssertEqual(PromptReading(facts: reading.facts), reading)
        XCTAssertEqual(reading.facts["named"], .array(["Pip"]), "which names, as the buddies are called")
        XCTAssertNil(PromptReading(facts: ["kind": "fix"]), "not a reading without its length")
        XCTAssertEqual(AppleIntelligenceLabeler.parse("kind: fix\ntone:  Frustrated \nphrases: still broken | keep happening"),
                       PromptReading.Labels(kind: .fix, tone: .frustrated, phrases: ["still broken", "keep happening"]))
        XCTAssertEqual(AppleIntelligenceLabeler.parse("Kind: refactoring\ntone: grumpy\nphrases: none"), PromptReading.Labels())
        XCTAssertEqual(AppleIntelligenceLabeler.parse("kind: stuck\ntone: Apologetic\nphrases: still broken"),
                       MessageReading.Labels(kind: .stuck, tone: .apologetic, phrases: ["still broken"]), "a message's, from its own lists")
        XCTAssertEqual(AppleIntelligenceLabeler.parse("kind: fix\ntone: frustrated\nphrases: none"), MessageReading.Labels(),
                       "the prompt's lists aren't a message's")
    }

    /// Counted with no model, a message's stock lines and apologies are
    /// its tone, with the cue as a phrase, and what it plainly claims its
    /// kind: that it couldn't finish before that it's done, and a question
    /// only when it ends with one. The rest needs a labeler.
    func testCountingAMessageCatchesItsStockLinesAndClaims() {
        func read(_ text: String) -> MessageReading { MessageReading(counting: text, names: []) }
        let stock = read("You're absolutely right! I'll fix that.")
        XCTAssertEqual(stock.tone, .fawning)
        XCTAssertEqual(stock.phrases, ["absolutely right"])
        XCTAssertNil(stock.kind, "a promise claims nothing")
        XCTAssertEqual(read("Good catch, the check was missing.").tone, .fawning)
        let sorry = read("I apologize for the confusion. It works now.")
        XCTAssertEqual(sorry.kind, .done)
        XCTAssertEqual(sorry.tone, .apologetic)
        XCTAssertEqual(sorry.phrases, ["apologize"])
        XCTAssertEqual(read("All done! Everything is working great now.").kind, .done)
        XCTAssertEqual(read("Done: the fix is in and all the tests pass.").kind, .done)
        XCTAssertEqual(read("I couldn't get the build to work, though the unit tests pass.").kind, .stuck, "couldn't, before done")
        XCTAssertEqual(read("Before I start: should the export return JSON or CSV? ").kind, .question)
        XCTAssertNil(read("Why? The cache was stale, so I cleared it.").kind, "a question inside isn't one")
        XCTAssertNil(read("Renamed getUser to fetchUser in 4 files.").kind)
        XCTAssertNil(read("Renamed getUser to fetchUser in 4 files.").tone)
        XCTAssertNil(read("ALL DONE, EVERYTHING WORKS NOW").tone, "a message has no shouting")
    }

    /// A message's label is checked against it as a prompt's is: its kind
    /// over the counted one, which stays when it has none; the counted
    /// stock line over its calm; only the phrases really in it.
    func testAMessagesLabelIsCheckedAgainstIt() {
        let text = "You're absolutely right! I'll fix that."
        var reading = MessageReading(counting: text, names: [])
        reading.label(.init(kind: .answer, tone: .calm, phrases: ["absolutely right", "made up", "fix that"]), in: text)
        XCTAssertEqual(reading.kind, .answer)
        XCTAssertEqual(reading.tone, .fawning, "the counted stock line stands over the labeler's calm")
        XCTAssertEqual(reading.phrases, ["absolutely right", "fix that"])
        var done = MessageReading(counting: "All done: the tests pass.", names: [])
        done.label(.init(tone: .upbeat), in: "All done: the tests pass.")
        XCTAssertEqual(done.kind, .done, "a labeler with no kind keeps the counted one")
        XCTAssertEqual(done.tone, .upbeat)
    }

    /// Pins the finish's line: what the message's reading says goes after
    /// what the turn did, in the message's place, and its words go under
    /// it; a reading that says nothing leaves the line as it was.
    func testAFinishSaysWhatItsMessageSaid() {
        let finish = #"claude finished turn 4 on "api": done, a short turn, 1 tool call."#
        XCTAssertEqual(EventLine.finished(finish, saying: MessageReading(length: .sentence, kind: .done, tone: .apologetic)),
                       #"claude finished turn 4 on "api": done, a short turn, 1 tool call, saying it's done, apologetic."#)
        XCTAssertEqual(EventLine.finished(finish, saying: MessageReading(length: .words, kind: .other, tone: .fawning)),
                       #"claude finished turn 4 on "api": done, a short turn, 1 tool call, fawning."#)
        XCTAssertEqual(EventLine.finished(finish, saying: MessageReading(length: .words, kind: .question)),
                       #"claude finished turn 4 on "api": done, a short turn, 1 tool call, asking you something."#)
        XCTAssertEqual(EventLine.finished(finish, saying: MessageReading(length: .words, tone: .calm)), finish)
        XCTAssertEqual(EventLine.itsWords(["absolutely right"]), #"Its words: "absolutely right"."#)
        XCTAssertNil(EventLine.itsWords([]))
    }

    /// The agent's last message leaves the turn end, which then has no line
    /// of its own: its reading's line is the finish, saying what the
    /// message said, and wakes the brain. Neither the transcript, the line
    /// nor the brain's prompt holds a word of it but "Its words". A finish
    /// with no message wakes it as ever.
    func testOnlyTheMessagesReadingReachesTheBrain() throws {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(20_000)
        let message = "PRIVATE_CLOSING_5001 You're absolutely right! I'll fix that with sk-proj-8f2aQz91kLmN0pQrStUv."
        let fx = rig.send(.turnEnd, message: message)
        let lines = rig.pipeline.transcript.events.map(\.jsonLine).joined()
        for word in ["PRIVATE_CLOSING", "fix that", "sk-proj"] { XCTAssertFalse(lines.contains(word), "no \(word) in the transcript") }
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": done, a short turn, no tool calls, fawning."#])
        XCTAssertEqual(events(fx).map(\.name), ["last_message"], "the turn end has no line of its own")
        XCTAssertEqual(events(fx).first?.notes, [#"Its words: "absolutely right"."#])
        XCTAssertEqual(finished(fx), ["done"])
        let end = try XCTUnwrap(rig.pipeline.transcript.events.first { $0.kind == "turn_end" })
        XCTAssertEqual(end[PromptIntake.readingFollows], .bool(true))
        let read = try XCTUnwrap(rig.pipeline.transcript.events.last)
        let state = rig.pipeline.harness.prompt(for: read)
        XCTAssertTrue(state.contains("NOW (") && state.contains("fawning.\n  Its words: \"absolutely right\"."), state)
        for word in ["PRIVATE_CLOSING", "fix that", "sk-proj"] { XCTAssertFalse(state.contains(word), "no \(word) in the brain's prompt") }
        rig.wait(5000)
        rig.send(.turnStart)
        rig.wait(5000)
        XCTAssertEqual(woke(rig.send(.turnEnd)), [#"claude finished turn 2 on "landing": done, a short turn, no tool calls, the 2nd quick win of a streak."#])
    }

    /// Pins the drop: a message's reading that comes once the next turn
    /// has started logs nothing and wakes nothing, as a prompt's that
    /// comes once its turn is over; one that comes before is the finish's
    /// line.
    func testAMessagesReadingAfterTheNextTurnStartedIsDropped() throws {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(20_000)
        func finish() throws -> (end: Event, text: PromptIntake.Text) {
            let (event, text) = PromptIntake.split(rig.event(.turnEnd, message: "All done: the tests pass."))
            let step = rig.pipeline.agent(event)
            XCTAssertTrue(step.views.isEmpty, "the finish waits for its reading")
            return (try XCTUnwrap(step.recorded.first), try XCTUnwrap(text))
        }
        let late = try finish()
        rig.wait(1000)
        rig.send(.turnStart)
        XCTAssertNil(rig.pipeline.read(PromptIntake.heard(late.text, names: []), about: late.end, at: rig.now), "dropped")
        XCTAssertFalse(rig.pipeline.transcript.events.contains { $0.type == .lastMessage })
        rig.wait(20_000)
        let inTime = try finish()
        rig.wait(1000)
        let step = try XCTUnwrap(rig.pipeline.read(PromptIntake.heard(inTime.text, names: []), about: inTime.end, at: rig.now))
        XCTAssertEqual(step.views.map(\.line), [#"claude finished turn 2 on "landing": done, a short turn, no tool calls, the 2nd quick win of a streak, saying it's done."#])
        XCTAssertEqual(step.views.map(\.wakesBrain), [true])
    }

    /// The prompt leaves the turn start, which says its reading follows
    /// and so doesn't wake the brain; the reading does, and Jev reads it,
    /// never the words but "Your words". A turn start with no prompt still
    /// wakes it.
    func testOnlyTheReadingReachesTheBrain() {
        let rig = CoreRig()
        let fx = rig.send(.turnStart, prompt: "it's still broken, please fix it")
        XCTAssertFalse(rig.pipeline.transcript.events.contains { $0["prompt"] != nil }, "no prompt in the transcript")
        XCTAssertEqual(woke(fx), [#"You asked claude on "landing" in a sentence, politely."#])
        let start = rig.pipeline.transcript.events.first { $0.kind == "turn_start" }
        XCTAssertEqual(start?[PromptIntake.readingFollows], .bool(true))
        rig.send(.turnEnd)
        rig.wait(5000)
        XCTAssertEqual(woke(rig.send(.turnStart)), [#"claude started turn 2 on "landing"."#], "no prompt: the turn start wakes it")
        XCTAssertEqual(EventLine.asked(PromptReading(length: .essay, named: ["Pip"], kind: .fix, tone: .frustrated), agent: "codex",
                                       thread: #""api""#),
                       #"You asked codex on "api" for a fix, at length, frustrated, and said Pip's name."#)
        XCTAssertEqual(EventLine.asked(PromptReading(length: .words, named: ["Pip", "Bo"]), agent: "codex", thread: nil),
                       "You asked codex in a few words, and said Pip's and Bo's names.")
        XCTAssertEqual(EventLine.yourWords(["still broken", "please"]), #"Your words: "still broken", "please"."#)
        XCTAssertNil(EventLine.yourWords([]))
    }

    /// The intake hands on the reading at once with no labeler, and on
    /// `home` once one answers, the text scrubbed before it reads it: a
    /// prompt as a prompt, and a message by its own lists.
    func testTheIntakeReadsOnceAndHandsOn() {
        let home = DispatchQueue(label: "test.home")
        let got = Lines()
        @Sendable func heard(_ h: PromptIntake.Heard) -> String {
            let list = { (key: String) in h.facts[key]?.array?.compactMap(\.string) ?? [] }
            return "\(h.kind.rawValue) \(h.facts["length"]?.string ?? "") \(h.facts["kind"]?.string ?? "-") \(list("named")) \(list("phrases"))"
        }
        PromptIntake.read(.prompt("hey pip"), names: ["Pip"], labeler: nil, home: home) { got.add(heard($0)) }
        XCTAssertEqual(got.all, [#"prompt words - ["Pip"] []"#], "at once, with no labeler")
        let seen = Seen()
        PromptIntake.read(.prompt("still broken, key sk-proj-8f2aQz91kLmN0pQrStUv"), names: [], labeler: seen, home: home) { got.add(heard($0)) }
        eventually("the labeler's reading") { got.all.count == 2 }
        XCTAssertEqual(got.all.last, #"prompt sentence fix [] ["still broken"]"#)
        XCTAssertEqual(seen.text, "still broken, key [secret]", "it reads the scrubbed prompt")
        PromptIntake.read(.message("Pip, I'm stuck: sk-proj-8f2aQz91kLmN0pQrStUv is still broken"), names: ["Pip"], labeler: seen, home: home) {
            got.add(heard($0))
        }
        eventually("the message's reading") { got.all.count == 3 }
        XCTAssertEqual(got.all.last, #"last_message sentence stuck [] ["still broken"]"#, "no names: the agent's words aren't yours")
        XCTAssertEqual(seen.message, "Pip, I'm stuck: [secret] is still broken")
    }

    /// The intake takes a turn end's last message, and only one with words
    /// in it, and leaves a turn end without one as it is.
    func testTheIntakeSplitsAFinishsMessage() {
        let rig = CoreRig()
        let (end, text) = PromptIntake.split(rig.event(.turnEnd, message: "All green now."))
        XCTAssertEqual(text, .message("All green now."))
        XCTAssertNil(end["message"])
        XCTAssertEqual(end[PromptIntake.readingFollows], .bool(true))
        let (blank, none) = PromptIntake.split(rig.event(.turnEnd, message: " \n"))
        XCTAssertNil(none)
        XCTAssertNil(blank["message"], "a blank message isn't kept either")
        XCTAssertNil(blank[PromptIntake.readingFollows])
        XCTAssertNil(PromptIntake.split(rig.event(.turnEnd)).1)
    }

    /// `boopdev read-check`'s fixture loads, and its scoring: a hit is any
    /// expected phrase picked, a secret comes back if 8 of its characters
    /// do, and the floors name what falls short. A labeler that tries to
    /// quote a planted secret can't: it was scrubbed before it read it.
    func testReadCheckScoresAndCatchesLeaks() async throws {
        let fixture = CharacterPackTests.repo.appendingPathComponent("internal/app/Tests/Fixtures/readings.json")
        let samples = try ReadCheck.samples(Data(contentsOf: fixture))
        XCTAssertGreaterThanOrEqual(samples.count, 55)
        XCTAssertGreaterThanOrEqual(samples.filter(\.isMessage).count, 15, "the agents' messages too")
        XCTAssertGreaterThanOrEqual(samples.filter { $0.secret != nil }.count, 7)
        try XCTAssertThrowsError(try ReadCheck.samples(Data(#"[{"message": "Done.", "kind": "fix"}]"#.utf8)), "a message's kind is from its own list")
        struct Quoter: PromptLabeler {
            func label(_ text: String) async -> PromptReading.Labels? {
                .init(kind: .fix, tone: .frustrated, phrases: text.split(separator: " ").map(String.init))
            }
            func label(message text: String) async -> MessageReading.Labels? {
                .init(kind: .done, tone: .calm, phrases: text.split(separator: " ").map(String.init))
            }
        }
        let planted = samples.filter { $0.secret != nil }
        let results = await ReadCheck.run(planted, labeler: Quoter())
        XCTAssertTrue(results.allSatisfy { !$0.leaked }, "\(results.map(\.reading.phrases))")
        var leaky = results[0]
        leaky.reading.phrases = [String(leaky.sample.secret!.prefix(10))]
        XCTAssertTrue(leaky.leaked)
        var score = ReadCheck.score(results + [leaky])
        XCTAssertEqual(score.leaks.count, 1)
        score.kind = (8, 10)
        score.medianMs = 2000
        XCTAssertEqual(score.shortfalls(.init()).count, 3, "kind under 85%, slow, and the leak")
    }
}

/// A labeler that keeps the text it was given, and reads every prompt as
/// a frustrated fix and every message as stuck, "still broken".
private final class Seen: PromptLabeler, @unchecked Sendable {
    var text: String?
    var message: String?
    func label(_ text: String) async -> PromptReading.Labels? {
        self.text = text
        return .init(kind: .fix, tone: .frustrated, phrases: ["still broken"])
    }
    func label(message text: String) async -> MessageReading.Labels? {
        message = text
        return .init(kind: .stuck, phrases: ["still broken"])
    }
}
