import Foundation

/// What the person does to Boop's memory from the popover: forget a note
/// for good, pin one so it never ages or changes, or forget what Boop
/// learned about them. You and Boop stays: it's Boop's, made by their care.
extension Runtime {
    /// Forgets the note `id`, for good: the dream's write never sees it again.
    public func forgetNote(_ id: Int) {
        home.async { [self] in editMemory { $0.notes.removeAll { $0.id == id } } }
    }

    /// Pins the note `id`, or lets it go: a pinned note never ages and the
    /// dream's write never changes it.
    public func pinNote(_ id: Int, _ pinned: Bool) {
        home.async { [self] in
            editMemory { m in
                if let i = m.notes.firstIndex(where: { $0.id == id }) { m.notes[i].pinned = pinned }
            }
        }
    }

    /// Forgets what Boop learned about you: You, Your work and Recently,
    /// and what the dreams count them from (`Memory.forgetAboutYou`). You
    /// and Boop stays.
    public func forgetAboutYou() {
        home.async { [self] in
            editMemory { m in
                m.notes.removeAll { !$0.section.lasting }
                m.recently = []
            }
            remembers?.forgetAboutYou()
            options.log("memory: forgot what Boop learned about you")
        }
    }

    /// Changes `memory.md` as the person asked, on `home`.
    func editMemory(_ change: (inout WrittenMemory) -> Void) {
        var m = memory.written()
        change(&m)
        do { try memory.keep(m, day: options.time.boopDay(options.wallClock())) } catch { options.log("memory: can't write memory.md: \(error)") }
        changed()
    }
}
