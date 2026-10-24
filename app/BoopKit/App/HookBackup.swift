import AgentHooks
import Foundation

/// A copy of each agent's settings from before Boop first changed them, in
/// the state directory's `backups/`: Claude Code's `settings.json`, and
/// Codex's `hooks.json` and `config.toml`. Made once and never replaced,
/// so it stays the file as it was before Boop, whatever Boop does after.
public enum HookBackup {
    public static let folder = "backups"

    /// The files an agent's hooks live in, and what each copy is called.
    static func files(_ installer: HookInstaller, _ agent: Agent) -> [(from: URL, name: String)] {
        switch agent {
        case .claude: [(installer.configURL(.claude), "claude-settings.json")]
        case .codex: [(installer.configURL(.codex), "codex-hooks.json"),
                      (installer.home.appendingPathComponent(".codex/config.toml"), "codex-config.toml")]
        }
    }

    /// Copies `agent`'s files into `stateDir/backups/` unless a copy is
    /// there already. A file that isn't there has nothing to keep. Returns
    /// the copies made now.
    @discardableResult
    public static func once(_ installer: HookInstaller, _ agent: Agent, stateDir: URL) -> [URL] {
        let fm = FileManager.default
        let dir = stateDir.appendingPathComponent(folder)
        return files(installer, agent).compactMap { file in
            let copy = dir.appendingPathComponent(file.name)
            let source = file.from.resolvingSymlinksInPath()
            guard !fm.fileExists(atPath: copy.path), fm.fileExists(atPath: source.path) else { return nil }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return (try? fm.copyItem(at: source, to: copy)) != nil ? copy : nil
        }
    }
}
