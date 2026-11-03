import AgentHooks
import Foundation
import MellowHarness

/// The lines view events are written as. Only facts shown to
/// Jev reach them.
public enum EventLine {
    /// A thread as the lines name it: `"fix-nav" (landing)`, or just
    /// `"landing"` when the name is the project.
    public static func thread(name: String, project: String) -> String {
        name == project ? "\"\(name)\"" : "\"\(name)\" (\(project))"
    }

    public static func turnStart(agent: String, turn: Int, thread: String) -> String {
        "\(agent) started turn \(turn) on \(thread)."
    }

    /// `claude finished turn 7 on "fix-nav" (landing): done, a very long
    /// turn, 12 tool calls.`: the outcome, the length band and how many
    /// tool calls it made; a done or failed one, how many checks failed on
    /// the way (`, after 2 failed checks`), so a failure that follows others
    /// reads as more than the first, and a finish that finally worked as
    /// hard-won: the brain can't count them back in HISTORY.
    /// A turn whose edits removed `bigDeletion` lines or more, net, says
    /// how many are gone (`, 1,200 lines gone`).
    public static func turnEnd(agent: String, turn: Int, thread: String, outcome: String, lengthMs: Int64,
                               tools: Int, failedChecks: Int = 0, ofStreak: Int = 0, linesGone: Int = 0) -> String {
        let how = outcome == "failed" || outcome == "stopped" ? outcome : "done"
        let after = outcome == "stopped" || failedChecks < 1 ? "" : failedChecks == 1 ? ", after a failed check"
            : ", after \(failedChecks) failed checks"
        let run = ofStreak < 2 ? "" : ", the \(nth(ofStreak)) quick win of a streak"
        let gone = linesGone < bigDeletion ? "" : ", \(linesGone.formatted(.number.locale(Locale(identifier: "en_US")))) lines gone"
        return "\(agent) finished turn \(turn) on \(thread): \(how), a \(Band.length(ms: lengthMs)) turn, \(toolCalls(tools))\(gone)\(after)\(run)."
    }

    /// The lines a turn must remove, net of those it added, for its finish
    /// to say how many are gone.
    public static let bigDeletion = 500

    /// Quick wins in a row come in streaks of this many, and a turn's
    /// check-ins in rounds of this many: the lines say which rung, and a
    /// long run starts the ladder again.
    public static let streak = 5, round = 4

    /// Which rung of a ladder of `size` the `n`th in a row is, from 1: the
    /// 6th quick win is the 1st of a new streak.
    public static func rung(_ n: Int, of size: Int) -> Int { n < 1 ? 0 : (n - 1) % size + 1 }

    static func nth(_ n: Int) -> String { (0..<4).contains(n) ? ["0th", "1st", "2nd", "3rd"][n] : "\(n)th" }

    /// The note on the work stream's moments that hit Boop, by their styles
    /// (`WorkStream.hits`): `Failed commands hit Boop in the face 3 times
    /// (seeing more stars by the last); a command timed out and landed on Boop's
    /// head.`
    public static func hits(_ styles: [String], name: String = CharacterPack.active.name) -> String? {
        var parts: [String] = []
        let bonks = styles.filter(WorkStream.ladder.contains)
        if !bonks.isEmpty {
            let times = bonks.count == 1 ? "once" : bonks.count == 2 ? "twice" : "\(bonks.count) times"
            let top = bonks.contains("throw") ? " (it threw the last one back)" : bonks.contains("bonk3") ? " (seeing more stars by the last)" : ""
            parts.append("failed commands hit \(name) in the face \(times)\(top)")
        }
        if styles.contains("timeout") { parts.append("a command timed out and landed on \(name)'s head") }
        if styles.contains("no") { parts.append("you said no to a request and \(name) flinched") }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: "; ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// A working check-in's note for its rung of a round, from the second:
    /// `Boop's 2nd check-in of a round on this turn.`; nil for the first.
    public static func checkIn(_ rung: Int, name: String = CharacterPack.active.name) -> String? {
        rung > 1 ? "\(name)'s \(nth(rung)) check-in of a round on this turn." : nil
    }

    static func toolCalls(_ n: Int) -> String {
        n == 0 ? "no tool calls" : n == 1 ? "1 tool call" : "\(n) tool calls"
    }

    /// The longest thing you said that the state quotes, in characters.
    public static let messageMax = 300

    /// `claude finished turn 4 on "api": done, a short turn, 1 tool call,
    /// saying it's done, apologetic.`: a finish's line with its last
    /// message's reading, never its words; as it was for a reading that
    /// says nothing.
    public static func finished(_ finish: String, saying r: MessageReading) -> String {
        let parts = [r.kind?.words, r.tone?.words].compactMap { $0 }
        guard !parts.isEmpty else { return finish }
        return (finish.hasSuffix(".") ? String(finish.dropLast()) : finish) + ", " + parts.joined(separator: ", ") + "."
    }

    /// `You asked claude on "api" for a fix, in a sentence, frustrated, and
    /// said Pip's name.`: your prompt's reading, never its words; with no
    /// labeler, only its length and the names said (`Pip's and Bo's names`).
    public static func asked(_ r: PromptReading, agent: String, thread: String?) -> String {
        let named = r.named.isEmpty ? nil : "and said " + listed(r.named.map { "\($0)'s" }) + (r.named.count > 1 ? " names" : " name")
        let parts = [r.kind?.words, r.length.words, r.tone?.words, named]
        let head = "You asked \(agent)" + (thread.map { " on \($0)" } ?? "")
        return head + " " + parts.compactMap { $0 }.joined(separator: ", ") + "."
    }

    /// `Your words: "still broken", "thank you".`, the phrases a sign may
    /// show; nil for none.
    public static func yourWords(_ phrases: [String]) -> String? { quoted("Your words", phrases) }

    /// `Its words: "absolutely right".`, the agent's.
    public static func itsWords(_ phrases: [String]) -> String? { quoted("Its words", phrases) }

    /// `label: "a", "b".`; nil for no phrases.
    static func quoted(_ label: String, _ phrases: [String]) -> String? {
        phrases.isEmpty ? nil : "\(label): " + phrases.map { "\"\($0)\"" }.joined(separator: ", ") + "."
    }

    /// Words on one line, cut to `messageMax`, after `label`. Nil for none.
    static func quote(_ label: String, _ text: String) -> String? {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        let cut = flat.count > messageMax ? String(flat.prefix(messageMax - 1)) + "…" : flat
        return "\(label): \"\(cut)\""
    }

    /// A tool use that woke the brain: a check that failed, or passed after
    /// failing. A check failing again says how many times in a row:
    /// `claude's tests failed again on "api", 3 times in a row.`
    public static func check(agent: String, topic: String, thread: String, failed: Bool, inARow: Int = 1) -> String {
        guard failed else { return "\(agent)'s \(topic) passed on \(thread) after failing." }
        return inARow > 1 ? "\(agent)'s \(topic) failed again on \(thread), \(inARow) times in a row." : "\(agent)'s \(topic) failed on \(thread)."
    }

    /// A work act's start or its result, for Jev to say something over what
    /// Boop already does by rule: the agent's clause, then the scene the pack
    /// draws for it, if it says one (`character.json`'s `acts`):
    /// `claude is pushing on "api". Boop has climbed on a rocket for it, by itself.`
    public static func actStarted(agent: String, kind: String, thread: String, name: String = CharacterPack.active.name,
                                  pack: CharacterPack = .active) -> String {
        let doing: String = switch kind {
        case "build": "\(agent) is building on \(thread)."
        case "tests": "\(agent) is running tests on \(thread)."
        default: "\(agent) is pushing on \(thread)."
        }
        return [doing, pack.actScene(kind, "start", name: name)].compactMap { $0 }.joined(separator: " ")
    }
    public static func actEnded(agent: String, kind: String, thread: String, passed: Bool, name: String = CharacterPack.active.name,
                                pack: CharacterPack = .active) -> String {
        let how: String = switch kind {
        case "build": passed ? "\(agent)'s build worked on \(thread), and the turn goes on." : "\(agent)'s build failed on \(thread)."
        case "tests": passed ? "\(agent)'s tests passed on \(thread), and the turn goes on." : "\(agent)'s tests failed on \(thread)."
        default: passed ? "\(agent)'s push went through on \(thread), and the turn goes on." : "\(agent)'s push failed on \(thread)."
        }
        return [how, pack.actScene(kind, passed ? "pass" : "fail", name: name)].compactMap { $0 }.joined(separator: " ")
    }

    /// Commands failing one after another (the work stream's failure
    /// ladder, `TranscriptView.wakingRungs`), while the turn goes on:
    /// `claude's commands keep failing on "api": 3 in 2 minutes, each one
    /// hitting Boop in the face. The turn goes on.`
    public static func failing(agent: String, thread: String, count: Int, name: String = CharacterPack.active.name) -> String {
        let minutes = WorkStream.ladderMs / 60_000
        return "\(agent)'s commands keep failing on \(thread): \(count) in \(minutes) minutes, each one hitting \(name) in the face. The turn goes on."
    }

    /// `You said to Boop: "…"`: what you said on push-to-talk, quoted and
    /// cut to `messageMax`, like your prompt. Nil for no words.
    public static func said(_ words: String, to name: String = CharacterPack.active.name) -> String? {
        quote("You said to \(name)", words)
    }

    /// `Pixel and Boop`: every buddy, for what you said to them all.
    static func everyone(_ buddies: [Buddy]) -> String { listed(buddies.map(\.name)) }

    /// `a`, `a and b`, `a, b and c`.
    static func listed(_ words: [String]) -> String {
        words.count < 2 ? words.joined() : words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    /// `You poked Boop.`, or `You poked Boop 4 times in a row.`; `while it
    /// slept` for a run's first poke with no session open, and `, again` (`again` for one poke) when
    /// the run before ended under `againMs` ago: the brain can't count the
    /// runs back in HISTORY.
    public static func poke(inARow count: Int, name: String = CharacterPack.active.name, asleep: Bool = false,
                            again: Bool = false) -> String {
        let poked = count <= 1 ? "You poked \(name)" : "You poked \(name) \(count) times in a row"
        if asleep { return poked + " while it slept." }
        if again { return poked + (count <= 1 ? " again." : ", again.") }
        return poked + "."
    }

    /// You stepping away from the Mac.
    public static let away = "You stepped away from the Mac."

    /// `You came back to the Mac after 12 hours away.`
    /// How long, in numbers past a short break: what it means (a night, a
    /// day, a weekend) is the steering's to say. The band stays in the
    /// line's facts (`Band.away`), for code that reads it.
    public static func back(ms: Int64) -> String {
        let minutes = ms / 60_000, hours = ms / 3_600_000, days = ms / 86_400_000
        if ms < shortBreakMs { return "You came back to the Mac after a short break." }
        if hours < 2 { return "You came back to the Mac after \(minutes) min away." }
        if hours < 48 { return "You came back to the Mac after \(hours) hours away." }
        return "You came back to the Mac after \(days) days away."
    }

    /// Away less than this is a short break, said with no number.
    public static let shortBreakMs: Int64 = 15 * 60_000

    /// You locked the Mac, with how long since the last lock, if the log
    /// knows: `You locked the Mac, first time in 3 h.` from `lockWhileMs`,
    /// `You locked the Mac again, 5 min after the last time.` under it. Facts
    /// only: what they mean is the steering's.
    public static func locked(sinceLastMs ms: Int64?) -> String {
        guard let ms else { return "You locked the Mac, first time in a while." }
        if ms >= lockWhileMs { return "You locked the Mac, first time in \(ms / 3_600_000) h." }
        return "You locked the Mac again, \(span(ms)) after the last time."
    }

    /// A lock this long after the last is the first in a while.
    public static let lockWhileMs: Int64 = 60 * 60_000

    /// You unlocked the Mac after a lock too short to be an away:
    /// `You unlocked the Mac after 2 min.`
    public static func unlocked(afterMs ms: Int64) -> String { "You unlocked the Mac after \(span(ms))." }

    /// A short span in whole minutes, or under a minute.
    static func span(_ ms: Int64) -> String { ms < 60_000 ? "under a minute" : "\(ms / 60_000) min" }

    /// You answered an ask: `You answered Boop's "fav snack?": cookie.`
    public static func answered(_ question: String, answer: String, name: String = CharacterPack.active.name) -> String {
        "You answered \(name)'s \"\(question)\": \(answer)."
    }

    /// Nobody answered an ask: `You didn't answer Boop's "fav snack?".`
    public static func unanswered(_ question: String, name: String = CharacterPack.active.name) -> String {
        "You didn't answer \(name)'s \"\(question)\"."
    }

    /// Under the line that tells the dream: `Boop dreamed about the last 2
    /// days: you stroked it 4 times; 7 turns on "api", 3 failed.`
    public static func dreamed(about: String, sentence: String, name: String = CharacterPack.active.name) -> String {
        "\(name) dreamed about \(about): \(sentence)."
    }

    /// `You shook Boop.`, or `You shook Boop 3 times in a row.`
    public static func shake(inARow count: Int, name: String = CharacterPack.active.name) -> String {
        count <= 1 ? "You shook \(name)." : "You shook \(name) \(count) times in a row."
    }

    /// Boop grew a stage: `Boop grew: it's a Sprout now.`
    public static func grew(_ stage: String, name: String = CharacterPack.active.name) -> String {
        "\(name) grew: it's a \(stage) now."
    }

    /// Boop's wish: made, and how it ended.
    public static func wished(_ kind: Core.WishKind, name: String = CharacterPack.active.name) -> String {
        "\(name) wished for \(kind.words)."
    }
    public static func wishEnded(_ how: Core.WishEnd, _ kind: Core.WishKind, waitedMs: Int64, name: String = CharacterPack.active.name) -> String {
        switch how {
        case .met: "You gave \(name) its wish: \(kind.words)."
        case .gaveup: "\(name) gave up on its wish for \(kind.words), after \(ContextSection.span(waitedMs)) with you here."
        case .closed: "\(name)'s wish for \(kind.words) ended with the day."
        }
    }

    /// A BOOT press that handed you an agent; what it opened is the core's
    /// record under it.
    public static func pressed(name: String = CharacterPack.active.name) -> String { "You pressed \(name)'s button." }
    public static func picked(name: String = CharacterPack.active.name) -> String {
        "You picked an agent from \(name)'s list."
    }

    public static func checkIn(hours: Int) -> String {
        "Nothing has happened for \(hours) hour\(hours == 1 ? "" : "s")."
    }

    /// The idle check-in: `Nothing has happened for 20 min; claude sits
    /// idle on "api".`, the thread last active.
    public static func idle(minutes: Int, agent: String, thread: String) -> String {
        "Nothing has happened for \(minutes) min; \(agent) sits idle on \(thread)."
    }

    /// The idle check-in with no session open: `Nothing has happened for
    /// 40 min; no agents are open.`
    public static func idle(minutes: Int) -> String {
        "Nothing has happened for \(minutes) min; no agents are open."
    }

    /// The agent's context compacted, mid-work.
    public static func compacted(agent: String, thread: String) -> String {
        "\(agent)'s context on \(thread) was compacted; it picks up where it left off."
    }

    /// You answered a request ("needs you" cleared): allowed or denied.
    /// The note on a finish heard late: it came while another agent's
    /// request showed, which held every reaction back.
    public static let finishedWhileYouWereBusy = "It finished while another agent needed you; nothing needs you now."

    public static func answered(agent: String, thread: String) -> String {
        "You answered \(agent) on \(thread)."
    }

    /// The working check-in: `claude is still working on "fix-nav"
    /// (landing), a long turn, running tests.`, the band of the turn so far
    /// and what its latest command or edit was about.
    public static func working(agent: String, thread: String, ms: Int64, topic: String? = nil) -> String {
        "\(agent) is still working on \(thread), a \(Band.length(ms: ms)) turn\(topic.flatMap { doing[$0] }.map { ", \($0)" } ?? "")."
    }

    /// What a turn is doing, by its latest topic, as a check-in says it.
    static let doing = ["tests": "running tests", "build": "running a build", "deploy": "deploying", "docs": "editing docs"]

    /// How to read HISTORY and NOW: Boop's own
    /// words for MellowHarness's layout, after the guide, with the
    /// creature's name.
    public static func reading(_ name: String = CharacterPack.active.name) -> String {
        """
            How to read HISTORY and NOW:
            - HISTORY is oldest first. Each line says how long ago it happened.
              Lines indented under it add to it: the words it quotes or a note,
              then what \(name) did. A line of what \(name) did ending in (in progress)
              hasn't finished yet.
            - NOW is what to react to. Its last line is what \(name) already did on
              its own, by reflex.
            """
    }

    /// The words the lines use, as the guide explains them after how to
    /// read the layout. Kept here, next to the lines.
    public static func words(_ name: String = CharacterPack.active.name) -> String { """
        - claude and codex are the person's coding agents.
        - A thread is one conversation with an agent, named after its workspace:
          "fix-nav" (landing) is the thread fix-nav in the project landing.
        - A turn is one request to a thread. It ends done, failed or stopped.
        - Tests, build, deploy and docs are what a command was about; failed
          means it ended with an error.
        - Turns are short (under a minute), long (under 5 minutes) or very
          long (5 minutes or more). Quick wins in a row are turns done in under
          \(TranscriptView.quickWinMs / 60_000) minutes, one after another on a thread, in streaks of up to \(streak): the
          line says which of its streak it is, and the \(nth(streak + 1)) starts a new one.
        - A check-in is \(name) looking in on a turn that's still going, in
          rounds of \(round); the note under it says which of its round it is.
        - "You asked" is the person's prompt to an agent, read on their Mac:
          what they asked for, how long, how they sound, and whether they said
          \(name)'s name. Never their words but the few under "Your words".
        - A finished turn says what the agent's last message said, read on the
          person's Mac: that it's done, couldn't finish, asks them something
          or only answers, and how it sounds. Never its words but the few under
          "Its words".
        - "You said to \(name)" quotes the person talking to \(name). It answers
          what they meant with a face and a reply: a move of its body and a
          sign, maybe a sound, a word or a phrase, never words of its own.
        - An idle check-in ("Nothing has happened for 20 min") means the person is
          around but no agent is working. A compacted context means the agent's
          memory was squeezed to make room; it carries on from a summary.
        - "You" stepping away from the Mac and coming back is the person. A
          short break is under 15 minutes; past that the line says how long,
          in minutes, hours or days.
        - "You locked the Mac" and "You unlocked the Mac" are the person's screen,
          and the person may be going. An unlock after a real break has no line
          of its own: that is "You came back".
        - "You answered \(name)'s" question is the person tapping one of the two
          answers \(name) held up; it answers as to anything said to it, with a
          glad face and a sign back for the answer.
        - "\(name) dreamed about Monday" is the day before, as \(name) kept it
          overnight, told the first time the person shows up after it.
        """
    }

    /// Boop hushed: from the Mac's button, or by what you said.
    public static func hushed(name: String, minutes: Int64, byApp: Bool) -> String {
        "You hushed \(name)\(byApp ? " from the Mac" : ""): it says nothing for \(minutes) min."
    }

    /// Boop free to talk again: its time ran out, or you said so.
    public static func unhushed(name: String, why: String) -> String {
        why == Core.By.timer.rawValue ? "\(name)'s hush ran out: it may talk again." : "You let \(name) talk again."
    }

    public static func needsYou(agent: String, thread: String) -> String {
        "\(agent) needs you on \(thread)."
    }

    /// The tool's category in a line's facts: agent-hooks'
    /// kind, but for planning, which the brain hears as `other`, as before
    /// the kinds moved there.
    public static func category(_ kind: ToolKind) -> String {
        kind == .planning ? ToolKind.other.rawValue : kind.rawValue
    }
}
