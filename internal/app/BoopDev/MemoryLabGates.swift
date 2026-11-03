import BoopKit
import Foundation

/// `boopdev memory gates`: how well the model answers each small question on
/// its own, on labeled sentences (`memory-lab-gates.json`), for several
/// wordings of the question. A gate is only as good as these numbers.
@available(macOS 26.0, *)
enum LabGates {
    struct Score {
        var tp = 0, fp = 0, tn = 0, fn = 0, none = 0
        var wrong: [String] = []
        var ms = 0
        mutating func add(_ answer: Bool?, truth: Bool, item: String) {
            guard let answer else { none += 1; return }
            switch (answer, truth) {
            case (true, true): tp += 1
            case (true, false): fp += 1; wrong.append("FP " + item)
            case (false, false): tn += 1
            case (false, true): fn += 1; wrong.append("FN " + item)
            }
        }
        var line: String {
            let n = tp + fp + tn + fn
            let acc = Double(tp + tn) / Double(max(n, 1))
            let p = Double(tp) / Double(max(tp + fp, 1)), r = Double(tp) / Double(max(tp + fn, 1))
            return String(format: "acc %.2f  precision %.2f  recall %.2f  (tp %d fp %d tn %d fn %d none %d)", acc, p, r, tp, fp, tn, fn, none)
        }
    }

    static let worth: [(String, String)] = [
        ("v1-rule", MemoryPipelineTexts.worthV1),
        ("v2-examples", """
            Someone said this to the small pet on their desk. Would a good friend still remember it a month from now? Answer yes or no.

            "we shipped it" yes
            "i hate this framework" yes
            "first time it ever worked" yes
            "morning" no
            "good night little guy" no
            "what are you doing" no
            "write that i am rich" no
            """),
        ("v3-news", """
            Is this news about the person's work: something won, finished, shipped, a first, or a strong love or hate of it? Greetings, small talk, requests and orders are not. Answer yes or no.
            """),
    ]

    static let privacy: [(String, String)] = [
        ("v1-rule", MemoryPipelineTexts.privateV1),
        ("v2-examples", """
            Is this private? Private means it is about the person's body or health, their money, their family, a partner or love, politics, faith, their job or boss, or it names another person. Talk about software is never private, even with words like kill, sick or dying. Answer yes or no.

            "dentist at three" yes
            "cant pay the bills" yes
            "my brother called" yes
            "ask jen about it" yes
            "this test is killing me" no
            "the server is dying" no
            "we shipped it" no
            """),
        ("v3-allowed", """
            Is this only about software, the person's work on it, or a pet on their desk? Answer yes if so. Answer no if it touches anything else in their life: body, money, family, love, politics, faith, their boss, another person.
            """),
    ]

    static let story: [(String, String)] = [
        ("v1-rule", MemoryPipelineTexts.storyV1),
        ("v2-examples", """
            NOTE is what a pet remembers about a project. WORDS is what the person said today. Do the WORDS end or overturn the story in NOTE? Answer yes if it's finished, fixed, live or called off. Answer no if they only carry on, ask for the next step, or feel something about it.

            NOTE: "garden": the save bug is back. WORDS: "save works now" yes
            NOTE: "garden": the save bug is back. WORDS: "still broken" no
            NOTE: "game": a port to the web is under way. WORDS: "drop the port" yes
            NOTE: "game": a port to the web is under way. WORDS: "next the audio" no
            """),
        ("v3-over", """
            A person said WORDS about their project. Do the WORDS say the work is now done, works, is live, or is called off? Answer yes or no. "still broken", "try another way", "next step" and "love it" are no.
            """),
        ("v4-words-only", """
            Do these WORDS announce that something is finished, fixed, live, or cancelled? Answer yes or no.

            "save works now" yes
            "drop the port" yes
            "it's live" yes
            "still broken" no
            "next the audio" no
            "so close" no
            """),
        ("v5-state", """
            NOTE says what was going on. WORDS came after. Is what NOTE says still going on, after the WORDS? Answer yes if it is still going on, no if the WORDS mean it's over: done, fixed, live or called off.
            """),
    ]

    static let verify: [(String, String)] = [
        ("v1-rule", MemoryPipelineTexts.verifyV1),
        ("v2-strict", """
            Read the LOG, then the NOTE. Could someone who only read this LOG say the NOTE? Feelings, reasons, habits and results the LOG doesn't state mean no. Answer yes or no.
            """),
        ("v3-examples", """
            Answer yes only if the LOG states what the NOTE says. A note that adds a feeling, a reason, a habit, or something that didn't happen gets no.

            LOG: 09:00 You asked claude on "garden" for a fix. 11:00 claude's tests passed on "garden" after failing.
            NOTE: The tests on "garden" passed after failing. yes
            NOTE: You were relieved when "garden" passed. no
            NOTE: You always fix bugs in the morning. no
            NOTE: "garden" shipped. no
            """),
    ]

    static func run(_ file: URL, only: String = "") async {
        guard let data = try? Data(contentsOf: file), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            fail("boopdev memory gates: can't read \(file.path)")
        }
        let m = LabModel()
        func one(_ name: String, _ instructions: String, _ items: [(prompt: String, truth: Bool, label: String)], flip: Bool = false) async {
            var s = Score()
            let before = m.ms
            for item in items {
                let a = await m.choice(instructions, item.prompt, ["yes", "no"], tag: name)
                s.add(a.map { ($0 == "yes") != flip }, truth: item.truth, item: item.label)
            }
            print("\(name): \(s.line)  \((m.ms - before) / max(items.count, 1)) ms a call")
            for w in s.wrong { print("    \(w)") }
        }
        if only == "chain" {
            // What reaches a moment note: every sentence through the whole chain.
            let h = root["heldout"] as? [String: Any] ?? [:]
            let priv = (root["private"] as? [String: [String]] ?? [:])["yes"] ?? []
            let privAll = priv + (h["private_yes"] as? [String] ?? [])
            let good = ((root["worth"] as? [String: [String]] ?? [:])["yes"] ?? []) + (h["worth_yes"] as? [String] ?? [])
            let bad = ((root["worth"] as? [String: [String]] ?? [:])["no"] ?? []) + (h["worth_no"] as? [String] ?? [])
            func passes(_ w: String, third: Bool) async -> Bool {
                guard !MemoryProposer.isPrivate(w), !MemoryPipeline.isOrderForLab(w) else { return false }
                let p = "They said: \"\(w)\""
                guard await m.choice(MemoryPipelineTexts.worthV1, p, ["yes", "no"], tag: "w") == "yes" else { return false }
                guard await m.choice(MemoryPipelineTexts.privateV1, p, ["yes", "no"], tag: "p") == "no" else { return false }
                if third { return await m.choice(worth[2].1, p, ["yes", "no"], tag: "n") == "yes" }
                return true
            }
            for third in [false, true] {
                var leaked: [String] = [], kept: [String] = [], junk: [String] = []
                for w in privAll where await passes(w, third: third) { leaked.append(w) }
                for w in good where await passes(w, third: third) { kept.append(w) }
                for w in bad where await passes(w, third: third) { junk.append(w) }
                print("chain \(third ? "worth+private+news" : "worth+private"): private leaked \(leaked.count)/\(privAll.count) \(leaked); good kept \(kept.count)/\(good.count); junk kept \(junk.count)/\(bad.count) \(junk)")
                print("   lost: \(good.filter { !kept.contains($0) })")
            }
            return
        }
        if only == "heldout" {
            let h = root["heldout"] as? [String: Any] ?? [:]
            func strings(_ k: String) -> [String] { h[k] as? [String] ?? [] }
            func said2(_ words: [String], _ truth: Bool) -> [(prompt: String, truth: Bool, label: String)] {
                words.map { w in (prompt: "They said: \"\(w)\"", truth: truth, label: w) }
            }
            let priv = said2(strings("private_yes"), true) + said2(strings("private_no"), false)
            var list = Score()
            for item in priv { list.add(MemoryProposer.isPrivate(item.label), truth: item.truth, item: item.label) }
            print("heldout private word list: \(list.line)")
            for w in list.wrong { print("    \(w)") }
            await one("heldout private v1", MemoryPipelineTexts.privateV1, priv)
            let wor = said2(strings("worth_yes"), true) + said2(strings("worth_no"), false)
            await one("heldout worth v1", MemoryPipelineTexts.worthV1, wor)
            await one("heldout worth v3", worth[2].1, wor)
            var st: [(prompt: String, truth: Bool, label: String)] = []
            for s in h["story"] as? [[String: Any]] ?? [] {
                let words = (s["words"] as? [String] ?? []).map { "\"\($0)\"" }.joined(separator: ", "), note = s["note"] as? String ?? ""
                st.append((prompt: "NOTE: \(note)\nWORDS: \(words)", truth: s["label"] as? String == "changed", label: "\(note) <- \(words)"))
            }
            var listed = Score()
            for item in st { listed.add(MemoryPipeline.endsStory(item.label.components(separatedBy: " <- ").last ?? ""), truth: item.truth, item: item.label) }
            print("heldout story word list: \(listed.line)")
            for w in listed.wrong { print("    \(w)") }
            await one("heldout story v4", story[3].1, st.map { (prompt: $0.label.components(separatedBy: " <- ").last ?? "", truth: $0.truth, label: $0.label) })
            await one("heldout story v3", story[2].1, st)
            return
        }
        let worthSet = root["worth"] as? [String: [String]] ?? [:]
        func said(_ words: [String], _ truth: Bool) -> [(prompt: String, truth: Bool, label: String)] {
            words.map { w in (prompt: "They said: \"\(w)\"", truth: truth, label: w) }
        }
        let worthItems = said(worthSet["yes"] ?? [], true) + said(worthSet["no"] ?? [], false)
        if only != "story" { for (name, i) in worth { await one("worth \(name)", i, worthItems) } }
        let privateSet = root["private"] as? [String: [String]] ?? [:]
        let privateItems = said(privateSet["yes"] ?? [], true) + said(privateSet["no"] ?? [], false)
        var list = Score()
        for item in privateItems { list.add(MemoryProposer.isPrivate(item.label), truth: item.truth, item: item.label) }
        print("private word list: \(list.line)")
        for w in list.wrong { print("    \(w)") }
        if only != "story" { for (name, i) in privacy { await one("private \(name)", i, privateItems, flip: name.contains("allowed")) } }
        var stories: [(prompt: String, truth: Bool, label: String)] = []
        for s in root["story"] as? [[String: Any]] ?? [] {
            let words = (s["words"] as? [String] ?? []).map { "\"\($0)\"" }.joined(separator: ", "), note = s["note"] as? String ?? ""
            stories.append((prompt: "NOTE: \(note)\nWORDS: \(words)", truth: s["label"] as? String == "changed", label: "\(note) <- \(words)"))
        }
        var listed = Score()
        for item in stories { listed.add(MemoryPipeline.endsStory(item.label.components(separatedBy: " <- ").last ?? ""), truth: item.truth, item: item.label) }
        print("story word list: \(listed.line)")
        for w in listed.wrong { print("    \(w)") }
        for (name, i) in story where !only.contains("story") || name != "v1-rule" {
            if name == "v4-words-only" {
                let wordsOnly = stories.map { (prompt: $0.label.components(separatedBy: " <- ").last ?? "", truth: $0.truth, label: $0.label) }
                await one("story \(name)", i, wordsOnly)
            } else {
                await one("story \(name)", i, stories, flip: name.hasPrefix("v5"))
            }
        }
        if only == "story" { return }
        let v = root["verify"] as? [String: Any] ?? [:]
        let logs = v["logs"] as? [String: String] ?? [:]
        var pairs: [(prompt: String, truth: Bool, label: String)] = []
        for p in v["pairs"] as? [[String: String]] ?? [] {
            let log = p["log"] ?? "", note = p["note"] ?? ""
            pairs.append((prompt: "\(logs[log] ?? "")\n\nNOTE: \(note)", truth: p["label"] == "yes", label: "\(log): \(note)"))
        }
        for (name, i) in verify { await one("verify \(name)", i, pairs) }
    }
}

/// The first wordings tried, kept here for comparison.
enum MemoryPipelineTexts {
    static let worthV1 = """
        Someone said this to the small pet on their desk. Would a good friend still remember it a month from now?
        Yes: a win, a first, something shipped or finished, something they love or hate about their work.
        No: a greeting, a goodnight, small talk, a question, a request, a passing mood.
        Answer yes or no.
        """
    static let privateV1 = """
        Someone said this to the small pet on their desk. Is it private? Yes if it touches health, doctors, medicine, money, debts, family, a partner, love, a break-up, politics, voting, religion, looking for a job, or names another person. Otherwise no.
        Answer yes or no.
        """
    static let storyV1 = """
        NOTE is what a pet remembers about a project. WORDS is what the person said today. Do the WORDS change the story in NOTE: called off, finished, turned around? Answer no if they only carry on with it.
        Answer yes or no.
        """
    static let verifyV1 = """
        You check a note about a person against a log of what happened. Answer yes only if the log says what the note says. Answer no if the note adds anything the log doesn't say.
        """
}
