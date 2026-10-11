import Dispatch
import Foundation

extension Runtime {
    /// Who a demo's scripted answers and moods are by, in the transcript
    /// and the log.
    public static let demoBy = "demo"

    /// Plays a demo: each beat happens when its time comes, as if it were
    /// real: a hook as a hook from the socket, and a tap, talk, a mood and
    /// the clock as the socket's dev lines do them. A beat's `answer` is a
    /// forced pass, so the actions keep their own rules.
    ///
    /// `beat` hears each beat as it happens and `done` the end, both on
    /// `home`.
    public func play(_ script: DemoScript, beat: @escaping @Sendable (DemoScript.Beat) -> Void = { _ in },
                     done: @escaping @Sendable () -> Void = {}) {
        let start = DispatchTime.now()
        options.log("demo: \(script.beats.count) beats over \(Int(script.length)) s")
        for b in script.beats {
            home.asyncAfter(deadline: start + b.at) { [self] in
                beat(b)  // first, so what it causes comes after it
                happen(b)
            }
            if let answer = b.answer {
                home.asyncAfter(deadline: start + b.at + b.after) { [self] in forcePass(answer, by: Runtime.demoBy, who: Runtime.demoBy) }
            }
        }
        home.asyncAfter(deadline: start + script.length) { [self] in
            options.log("demo: over")
            done()
        }
    }

    private func happen(_ b: DemoScript.Beat) {
        switch b.what {
        case .hook(var line):
            line.ts = options.wallClock()
            hook(line, received: options.clock())
        case .tap:
            tapped(who: Runtime.demoBy)
        case .talk(let words, let hold):
            listen(true, who: Runtime.demoBy)
            home.asyncAfter(deadline: .now() + hold) { [self] in said(words, by: .app, who: Runtime.demoBy) }
        case .mood(let mood):
            forceMood(mood, by: Runtime.demoBy, who: Runtime.demoBy)
        case .advance(let seconds):
            advanceClock(Int64(seconds * 1000), who: Runtime.demoBy)
        case .nothing:
            break
        }
    }
}
