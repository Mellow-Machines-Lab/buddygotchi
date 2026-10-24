import AgentHooks
import Foundation

/// Taking Boop off this Mac, as Settings' Uninstall does, and keeping its
/// memory: a Boop installed again is the same Boop.
public enum Uninstall {
    /// What it took out, and what it couldn't, in words for the log.
    public struct Result: Equatable, Sendable {
        public var removed: [String] = []
        public var problems: [String] = []
    }

    /// Takes out, in order: each agent's hooks (Boop's entries only, and
    /// only where there are some, since removing rewrites the agent's
    /// file), while `agent-hook` is still there to recognise them; the
    /// listing of Boop's socket in agent-hooks' folder; the copy of
    /// `agent-hook` in `stateDir/bin`; and the login item. Leaves
    /// `stateDir` itself: the memory, settings and transcript.
    public static func run(installer: HookInstaller, stateDir: URL, loginItem: LoginItem,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> Result {
        var result = Result()
        let fm = FileManager.default
        for agent in Agent.allCases {
            let ours: Bool = switch installer.health(agent) {
            case .installed, .outdated, .hooksOff: true
            // Without the client its entries can't be told apart from
            // none: remove them anyway when the agent's file is there.
            case .clientMissing: fm.fileExists(atPath: installer.configURL(agent).path)
            case .notInstalled, .unreadable: false
            }
            guard ours else { continue }
            do {
                try installer.remove(agent)
                result.removed.append("\(agent.rawValue)'s hooks")
            } catch {
                result.problems.append("\(agent.rawValue)'s hooks: \(error)")
            }
        }
        // The listing is a link to Boop's socket: only that one goes.
        let link = HookSocket.directory(environment: environment) + "/boop.sock"
        let socket = stateDir.appendingPathComponent("boop.sock").path
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == socket {
            do {
                try fm.removeItem(atPath: link)
                result.removed.append("the socket's listing")
            } catch {
                result.problems.append("the socket's listing: \(error)")
            }
        }
        let client = URL(fileURLWithPath: installer.hookPath)
        if fm.fileExists(atPath: client.path) {
            do {
                try fm.removeItem(at: client)
                result.removed.append(HookInstaller.client)
                // Its folder, if nothing else is in it.
                let bin = client.deletingLastPathComponent()
                if (try? fm.contentsOfDirectory(atPath: bin.path))?.isEmpty == true { try? fm.removeItem(at: bin) }
            } catch {
                result.problems.append("\(HookInstaller.client): \(error)")
            }
        }
        if [.on, .needsApproval].contains(loginItem.state()) {
            do {
                try loginItem.set(false)
                result.removed.append("opening at login")
            } catch {
                result.problems.append("opening at login: \(error)")
            }
        }
        return result
    }
}
