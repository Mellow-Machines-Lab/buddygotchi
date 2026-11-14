import Foundation

extension Runtime {
    /// Gives the one Boop a new name, as Settings' Rename asks: in
    /// `long-term.md`, through the memory store, with the time kept in
    /// `settings.json`, since a rename waits a week (`BuddyName`). This
    /// runtime goes on under the old name: the app starts a new one, which
    /// reads the new name everywhere it lives (the buddy's pack, the
    /// brain's prompt, the board's `state.buddy`, the popover) and sends it
    /// to the world on its first send, where the world's name filter
    /// applies. `done` gets whether it renamed (false for the same name),
    /// or why not, on `home`.
    public func rename(to name: String, _ done: @escaping @Sendable (Result<Bool, Refusal>) -> Void) {
        home.async { [self] in done(renameNow(name)) }
    }

    func renameNow(_ name: String) -> Result<Bool, Refusal> {
        // Several buddies each take their name from settings.json's `buddies`.
        guard !pipeline.several else { return .failure(Refusal("several buddies are named in settings.json")) }
        let new = BuddyName.trimmed(name)
        guard new != self.name else { return .success(false) }
        let wall = options.wallClock()
        if BuddyName.nextRename(after: settings.renamed, at: wall) != nil {
            return .failure(Refusal("\(self.name) was renamed less than a week ago"))
        }
        do {
            try memory.rename(to: new, today: options.time.day(wall))
        } catch let refusal as Refusal {
            return .failure(refusal)
        } catch {
            options.log("name: can't write the new name: \(error)")
            return .failure(Refusal("the new name couldn't be saved"))
        }
        saveSettings { $0.renamed = wall }
        options.log("name: renamed \(self.name) to \(new), from the next start")
        return .success(true)
    }
}
