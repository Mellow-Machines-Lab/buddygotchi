import Dispatch
import Foundation

extension Runtime {
    /// Who a demo's scripted answers are by, in the log.
    public static let demoBy = "demo"

    /// Plays a demo: each beat happens when its time comes, as if it were
    /// real, through the same doors: a hook as a hook from the socket, a
    /// tap as the device's, talk as the mic's. A beat's `answer` is a
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
                home.asyncAfter(deadline: start + b.at + b.after) { [self] in
                    dev(["dev": "answer", "answers": answer, "by": Runtime.demoBy])
                }
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
            dev(["dev": "tap"])
        case .talk(let words, let hold):
            dev(["dev": "listen", "on": true])
            home.asyncAfter(deadline: .now() + hold) { [self] in dev(["dev": "said", "words": words]) }
        case .mood(let mood):
            dev(["dev": "mood", "mood": mood])
        case .advance(let seconds):
            dev(["dev": "advance", "ms": Int64(seconds * 1000)])
        case .nothing:
            break
        }
    }

    private func dev(_ line: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: line) { dev(data) }
    }
}
