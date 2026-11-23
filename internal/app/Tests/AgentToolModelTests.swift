import Foundation
import XCTest
@testable import BoopKit

/// The dream's model on your own agent tool (`AgentToolModel`): how it's
/// found, how it's run unseen, and how its answers are read.
final class AgentToolModelTests: XCTestCase {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agenttool-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A stand-in tool: a script that prints `answer`.
    func fakeTool(_ name: String, in dir: URL, answer: String, exit: Int = 0) -> URL {
        let url = dir.appendingPathComponent(name)
        let script = "#!/bin/sh\ncat > /dev/null\nprintf '%s' '\(answer)'\nexit \(exit)\n"
        FileManager.default.createFile(atPath: url.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        return url
    }

    /// Claude Code first, then Codex; none found is nil.
    func testItFindsClaudeFirst() {
        let bin = tempDir(), home = tempDir(), folder = tempDir()
        XCTAssertNil(AgentToolModel.find(folder: folder, home: home, path: bin.path))
        _ = fakeTool("codex", in: bin, answer: "yes")
        XCTAssertEqual(AgentToolModel.find(folder: folder, home: home, path: bin.path)?.tool, .codex)
        _ = fakeTool("claude", in: bin, answer: "yes")
        XCTAssertEqual(AgentToolModel.find(folder: folder, home: home, path: bin.path)?.tool, .claude)
    }

    /// Run unseen: no settings (so no hooks), no MCP, no tools, no session
    /// kept; never `--bare`, which refuses a plan's login.
    func testItRunsUnseen() {
        let m = AgentToolModel(tool: .claude, executable: "/x/claude", folder: tempDir())
        let args = m.arguments(answerFile: URL(fileURLWithPath: "/tmp/a"))
        for flag in ["-p", "--strict-mcp-config", "--no-session-persistence", "--tools", "--setting-sources"] {
            XCTAssertTrue(args.contains(flag), flag)
        }
        XCTAssertFalse(args.contains("--bare"))
        let codex = AgentToolModel(tool: .codex, executable: "/x/codex", folder: tempDir()).arguments(answerFile: URL(fileURLWithPath: "/tmp/a"))
        XCTAssertTrue(codex.contains("--ephemeral"))
        XCTAssertTrue(codex.contains("features.hooks=false"))
        XCTAssertTrue(codex.contains("read-only"))
    }

    func testYesOrNo() {
        XCTAssertEqual(AgentToolModel.yesOrNo("Yes."), true)
        XCTAssertEqual(AgentToolModel.yesOrNo(" no\n"), false)
        XCTAssertNil(AgentToolModel.yesOrNo("It depends"))
    }

    /// Its answer comes back; a failing run is nil, which every question
    /// takes as no to writing anything.
    func testItAsksAndReads() async {
        let bin = tempDir(), folder = tempDir()
        let yes = AgentToolModel(tool: .claude, executable: fakeTool("claude", in: bin, answer: "yes").path, folder: folder)
        let a = await yes.yes("Is it worth keeping?", "They said: \"I ship on Fridays\"")
        XCTAssertEqual(a, true)
        let text = AgentToolModel(tool: .claude, executable: fakeTool("claude2", in: bin, answer: " you ship on fridays ").path, folder: folder)
        let t = await text.text("Say it.", "x", tokens: 20)
        XCTAssertEqual(t, "you ship on fridays")
        let broken = AgentToolModel(tool: .claude, executable: fakeTool("claude3", in: bin, answer: "yes", exit: 1).path, folder: folder)
        let b = await broken.yes("?", "x")
        XCTAssertNil(b)
    }

    /// The writer asks your agent tool first, else the Mac's model.
    func testTheWriterAsksTheAgentToolFirst() {
        let model = AgentToolModel(tool: .claude, executable: "/x/claude", folder: tempDir())
        let writer = MemoryPipelineWriter(agentTool: { model })
        let asked = writer.model
        let capped = (asked as? CappedModel) ?? ((asked as? FallbackModel)?.first as? CappedModel)
        XCTAssertTrue(capped?.model is AgentToolModel)
        XCTAssertEqual(capped?.most, AgentToolModel.questionsADream)
    }

    /// A small model at low effort, never the newest: the budget is tight.
    func testItAsksASmallModel() {
        let claude = AgentToolModel(tool: .claude, executable: "/x/claude", folder: tempDir()).arguments(answerFile: URL(fileURLWithPath: "/tmp/a"))
        XCTAssertEqual(claude.drop { $0 != "--model" }.dropFirst().first, "claude-sonnet-5-5")
        XCTAssertTrue(claude.contains("--max-budget-usd"))
        let codex = AgentToolModel(tool: .codex, executable: "/x/codex", folder: tempDir()).arguments(answerFile: URL(fileURLWithPath: "/tmp/a"))
        XCTAssertEqual(codex.drop { $0 != "--model" }.dropFirst().first, "gpt-6-luna")
    }

    /// Past its cap a dream's questions go to the next model.
    func testADreamAsksAtMostItsCap() async {
        let bin = tempDir(), folder = tempDir()
        let tool = AgentToolModel(tool: .claude, executable: fakeTool("claude", in: bin, answer: "yes").path, folder: folder)
        let capped = CappedModel(tool, most: 2)
        var answers: [Bool?] = []
        for _ in 0..<3 { answers.append(await capped.yes("?", "x")) }
        XCTAssertEqual(answers, [true, true, nil])
    }

    /// A question the agent tool leaves unanswered goes to the next model.
    func testAnUnansweredQuestionFallsBack() async {
        let bin = tempDir(), folder = tempDir()
        let broken = AgentToolModel(tool: .claude, executable: fakeTool("claude", in: bin, answer: "", exit: 1).path, folder: folder)
        let works = AgentToolModel(tool: .claude, executable: fakeTool("other", in: bin, answer: "no").path, folder: folder)
        let a = await FallbackModel(first: broken, then: works).yes("?", "x")
        XCTAssertEqual(a, false)
    }

    /// The switch is on unless you turn it off, and only an off is written.
    func testTheSwitchDefaultsOn() throws {
        XCTAssertTrue(AppSettings().agentsThink)
        var s = AppSettings()
        s.agentsThink = false
        let data = try JSONEncoder().encode(s)
        let off = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(off.agentsThink)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.agentsThink)
    }
}
