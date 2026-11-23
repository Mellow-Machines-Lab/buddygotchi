import AgentHooks
import BoopKit
import Foundation

// boop-cards: the tool server an agent talks to, to hand Boop a card
// (`CardTool`, `Card`). A Model Context Protocol server over stdio: the
// agent starts it, lists its two tools and calls them. Each call is checked,
// sent to every app listening for hooks as one line, and answered "ok" at
// once, whether or not Boop is there: it never blocks an agent, and nothing
// it returns is worth depending on.
//
// `boop-cards [claude|codex]`: the agent that runs it, claude unless named,
// which is how it finds that agent's process, and so whose card it is.
//
// With BOOP_CARDS_LOG set, each call is also appended to that file as a
// JSON line, for the test that asks whether agents send good cards.

let environment = ProcessInfo.processInfo.environment
let logPath = environment["BOOP_CARDS_LOG"]
let agentName = CommandLine.arguments.dropFirst().first ?? "claude"
/// The agent that started this server: the first ancestor that isn't a shell.
let agentProcess = AgentProcess.find(agent: agentName, env: environment)

func reply(_ id: Any?, result: [String: Any]? = nil, error: (Int, String)? = nil) {
    guard let id else { return }  // a notification takes no answer
    var message: [String: Any] = ["jsonrpc": "2.0", "id": id]
    if let error { message["error"] = ["code": error.0, "message": error.1] } else { message["result"] = result ?? [:] }
    guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func log(_ entry: [String: Any]) {
    guard let logPath, var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

/// The show, while it's tried: checked, logged and answered with what's
/// wrong, and sent nowhere yet.
let offersShow = environment["BOOP_CARDS_SHOW"] == "1"
func show(_ args: [String: Any]) -> String {
    let headline = (args["headline"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    var problems: [String] = []
    if headline.isEmpty { problems.append("show needs `headline`: the conclusion in a few plain words") }
    if headline.count > Show.headlineMost { problems.append("the headline is \(headline.count) characters: at most \(Show.headlineMost)") }
    if let svg = args["svg"] as? String {
        problems += Show.problems(svg: svg)
    } else if let image = args["image"] as? String {
        if !image.hasPrefix("/") || !FileManager.default.fileExists(atPath: image) { problems.append("`image` must be an absolute path to a PNG that exists") }
    } else {
        problems.append("show needs `svg` or `image`")
    }
    log(["ts": Int64(Date().timeIntervalSince1970 * 1000), "tool": "show", "args": args, "kept": problems.isEmpty,
         "problems": problems])
    return problems.isEmpty ? "ok" : "not shown: " + problems.joined(separator: "; ") + ". Fix it and call show again."
}

func call(_ name: String, _ args: [String: Any]) -> String {
    if name == "show", offersShow { return show(args) }
    guard let kind = Card.Kind(rawValue: name) else { return "no such tool" }
    let card = Card.make(kind, args)
    log(["ts": Int64(Date().timeIntervalSince1970 * 1000), "tool": name, "args": args, "kept": card != nil,
         "pid": agentProcess.map { Int($0.pid) } as Any? ?? NSNull()])
    // The one thing worth telling an agent: a call with nothing to show.
    guard let card else { return kind == .status ? "status needs `doing`: a few plain words" : "result needs `headline`: a few plain words" }
    let line = CardTool.line(card, process: agentProcess)
    for destination in HookSocket.destinations(environment: environment) { HookSocket.send(line, to: destination) }
    return "ok"
}

while let text = readLine(strippingNewline: true) {
    guard let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
          let method = message["method"] as? String else { continue }
    let id = message["id"], params = message["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        reply(id, result: ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                           "capabilities": ["tools": [String: Any]()],
                           "serverInfo": ["name": CardInstaller.name, "version": BoopVersion.current],
                           "instructions": CardTool.instructions + (offersShow ? CardTool.showInstructions : "")])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": CardTool.tools + (offersShow ? [CardTool.showTool] : [])])
    case "tools/call":
        let said = call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
        reply(id, result: ["content": [["type": "text", "text": said]], "isError": said != "ok"])
    default:
        if id != nil { reply(id, error: (-32601, "method not found")) }
    }
}
