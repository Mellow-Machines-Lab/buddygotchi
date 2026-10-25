import AgentHooks
import Foundation

/// Taking Boop off this Mac, as Settings' Uninstall does, and keeping its
/// memory: a Boop installed again is the same Boop.
public enum Uninstall {
    /// Takes out Boop's part of agent-hooks (`HookInstaller.uninstall`):
    /// its socket's listing, then, unless another app listens, each
    /// agent's hooks and the copy of `agent-hook` in `stateDir/bin`; and
    /// then its login item. Leaves `stateDir` itself: the memory, settings
    /// and transcript. Says what it took out, left and couldn't take out,
    /// in words for the log.
    public static func run(installer: HookInstaller, stateDir: URL, loginItem: LoginItem,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> HookInstaller.Uninstalled {
        // A copy of Boop on another folder is listed by its own name
        // (`AppSettings.copyName`) and hears the everyday Boop's hooks, so
        // it doesn't keep them.
        var result = installer.uninstall(as: "boop", socket: stateDir.appendingPathComponent("boop.sock").path,
                                         copies: { $0.hasPrefix(AppSettings.copyPrefix) }, environment: environment)
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
