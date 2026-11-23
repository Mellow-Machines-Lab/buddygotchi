import Foundation

/// The dream's model on the person's own coding agent (documentation/design/
/// brain.md, layer 3): Claude Code's `claude -p` or Codex's `codex exec`, run
/// by Boop while it sleeps, one question a process, with no tools, no hooks
/// and no session kept. It uses the plan the person already has; there's no
/// key and nothing to set up. Asked only at the dream, never while a turn of
/// theirs runs; a refusal, a failure or a timeout is nil, which every
/// question takes as no to writing anything.
public struct AgentToolModel: MemoryModel {
    public enum Tool: String, Sendable { case claude, codex }

    public let tool: Tool
    public let executable: String
    /// Where the runs start: a folder of Boop's own, so the agent keeps no
    /// trace in any project of yours.
    public let folder: URL
    public static let timeout: TimeInterval = 120

    public init(tool: Tool, executable: String, folder: URL) {
        self.tool = tool
        self.executable = executable
        self.folder = folder
    }

    /// The first agent tool found on this Mac, Claude Code first, or nil.
    /// An app launched from the Finder has a short PATH, so the usual
    /// install places are looked in too.
    public static func find(folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> AgentToolModel? {
        let dirs = path.split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".claude/local").path,
               "/opt/homebrew/bin", "/usr/local/bin"]
        for tool in [Tool.claude, .codex] {
            for dir in dirs {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(tool.rawValue).path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return AgentToolModel(tool: tool, executable: candidate, folder: folder)
                }
            }
        }
        return nil
    }

    /// The command line for one question. Claude Code: no setting sources
    /// (so none of your hooks run and Boop doesn't see itself as an agent at
    /// work), no MCP servers, no tools and no session kept. `--bare` would be
    /// simpler but refuses a plan's login. Codex: read-only, its hooks off,
    /// nothing kept, the answer written to a file.
    func arguments(answerFile: URL) -> [String] {
        switch tool {
        case .claude:
            ["-p", "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence", "--tools", "",
             "--output-format", "text"]
        case .codex:
            ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral", "-c", "features.hooks=false",
             "--output-last-message", answerFile.path, "-"]
        }
    }

    /// One question's whole text: the instructions, then the prompt.
    static func asking(_ instructions: String, _ prompt: String) -> String {
        instructions + "\n\nAnswer with only what is asked, and nothing else.\n\n" + prompt
    }

    public func text(_ instructions: String, _ prompt: String, tokens: Int) async -> String? {
        let words = max(8, tokens * 3 / 4)
        guard let answer = await run(Self.asking(instructions + " Keep it under \(words) words.", prompt)) else { return nil }
        let t = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public func yes(_ instructions: String, _ prompt: String) async -> Bool? {
        guard let answer = await run(Self.asking(instructions, prompt) + "\n\nAnswer yes or no, one word.") else { return nil }
        return Self.yesOrNo(answer)
    }

    /// A one-word answer read as yes or no; anything else is nil.
    static func yesOrNo(_ answer: String) -> Bool? {
        let w = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if w == "yes" || w.hasPrefix("yes") { return true }
        if w == "no" || w.hasPrefix("no") { return false }
        return nil
    }

    /// Runs the tool on `text` (on stdin), off the caller's queue, and
    /// returns its answer, or nil on a failure or past the timeout.
    func run(_ text: String) async -> String? {
        await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async { done.resume(returning: runNow(text)) }
        }
    }

    func runNow(_ text: String) -> String? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let answerFile = folder.appendingPathComponent("answer-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: answerFile) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(answerFile: answerFile)
        process.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        // Its hooks report nowhere: Boop never hears its own dream.
        env["AGENT_HOOKS_SOCKET"] = folder.appendingPathComponent("nobody.sock").path
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        let ended = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            ended.signal()
        }
        if ended.wait(timeout: .now() + Self.timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        if tool == .codex { return try? String(contentsOf: answerFile, encoding: .utf8) }
        return String(data: data, encoding: .utf8)
    }
}

/// Asks `first`, and `then` only for a question `first` leaves unanswered.
struct FallbackModel: MemoryModel {
    let first: MemoryModel, then: MemoryModel

    func text(_ instructions: String, _ prompt: String, tokens: Int) async -> String? {
        if let t = await first.text(instructions, prompt, tokens: tokens) { return t }
        return await then.text(instructions, prompt, tokens: tokens)
    }

    func yes(_ instructions: String, _ prompt: String) async -> Bool? {
        if let y = await first.yes(instructions, prompt) { return y }
        return await then.yes(instructions, prompt)
    }
}
