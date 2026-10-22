import AVFoundation
import BoopKit
import Foundation
@preconcurrency import Speech

/// Boop's ears: the Mac's mic, while Settings has Ears on, listening for
/// its name, a few words and three kinds of sound. Recognition runs on the
/// Mac only, or Ears doesn't start. The samples go to the recogniser and to
/// a level and pitch meter, and are never written anywhere; `Hearing`
/// decides what was heard, and only that word or sound leaves, through
/// `heard`. Push-to-talk takes the mic while it's held (`pause`).
final class Ears: @unchecked Sendable {
    /// Apple's recogniser ends a request after about a minute: a fresh one
    /// before that.
    static let restartSeconds = 50.0
    /// The pitch meter's rate: every 4th sample of 48 kHz, enough for a
    /// voice's pitch.
    static let pitchRate = 12_000.0

    let queue = DispatchQueue(label: "boop.ears")
    let log: (String) -> Void
    let authorize: (@escaping @Sendable (String?) -> Void) -> Void
    let heard: @Sendable (String, Bool) -> Void
    let name: String
    let recognizer = SFSpeechRecognizer()
    var hearing: Hearing
    var detector = SoundDetector()
    var engine: AVAudioEngine?
    var task: SFSpeechRecognitionTask?
    /// The request the tap feeds, swapped on each restart: read on the audio
    /// thread, so behind a lock.
    let lock = NSLock()
    var request: SFSpeechAudioBufferRecognitionRequest?
    /// Whether Ears should be listening, and whether push-to-talk has the
    /// mic for now.
    var wanted = false
    var paused = false
    /// Counts recognition requests, so a late result from an old one can't
    /// touch the next.
    var session = 0

    init(name: String, log: @escaping (String) -> Void, authorize: @escaping (@escaping @Sendable (String?) -> Void) -> Void,
         heard: @escaping @Sendable (String, Bool) -> Void) {
        self.name = name
        self.log = log
        self.authorize = authorize
        self.heard = heard
        hearing = Hearing(name: name)
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Starts listening, asking for the mic and speech recognition first if
    /// need be; `failed` gets why it can't. Any thread.
    func start(failed: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            wanted = true
            authorize { why in
                self.queue.async {
                    guard self.wanted else { return }
                    if let why = why ?? self.begin() {
                        self.wanted = false
                        failed(why)
                    }
                }
            }
        }
    }

    /// Stops listening. Any thread.
    func stop() {
        queue.async { [self] in
            wanted = false
            end()
        }
    }

    /// Push-to-talk takes the mic until `resume`.
    func pause() {
        queue.async { [self] in
            paused = true
            end()
        }
    }

    func resume() {
        queue.async { [self] in
            paused = false
            if wanted, engine == nil, let why = begin() { log("ears: can't start again: \(why)") }
        }
    }

    /// On `queue`: the mic and the recogniser on, or why not.
    private func begin() -> String? {
        guard !paused, engine == nil else { return nil }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return "On-device speech recognition isn't available on this Mac."
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return "No microphone is connected." }
        let step = max(1, Int(format.sampleRate / Self.pitchRate))
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.withLock { self.request }?.append(buffer)
            let (level, pitch) = Self.measure(buffer, step: step, rate: format.sampleRate / Double(step))
            self.queue.async {
                if let sound = self.detector.feed(levelDb: level, pitchHz: pitch, at: Self.now()),
                   let h = self.hearing.sound(sound, at: Self.now()) {
                    self.heard(h.what, h.misheard)
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            log("ears: can't start the mic: \(error)")
            return "The Mac's microphone couldn't start."
        }
        self.engine = engine
        listen(recognizer)
        log("ears: listening")
        return nil
    }

    /// On `queue`: a fresh recognition request, restarted before Apple's
    /// limit and whenever one ends.
    private func listen(_ recognizer: SFSpeechRecognizer) {
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = Hearing.phrases(name: name)
        lock.withLock { self.request = request }
        hearing.newUtterance()
        session += 1
        let this = session
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.session == this else { return }
                if let text = result?.bestTranscription.formattedString, let h = self.hearing.words(text, at: Self.now()) {
                    self.heard(h.what, h.misheard)
                }
                if error != nil || result?.isFinal == true, self.engine != nil { self.listen(recognizer) }
            }
        }
        queue.asyncAfter(deadline: .now() + Self.restartSeconds) { [weak self] in
            guard let self, self.session == this, self.engine != nil else { return }
            request.endAudio()
            self.listen(recognizer)
        }
    }

    /// On `queue`: the mic and the recogniser off.
    private func end() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        lock.withLock { request?.endAudio(); request = nil }
        task?.cancel()
        task = nil
        session += 1
        log("ears: off")
    }

    /// A buffer's level in dBFS, and its pitch in Hz when it's voiced: its
    /// first channel, every `step`th sample, by autocorrelation.
    static func measure(_ buffer: AVAudioPCMBuffer, step: Int, rate: Double) -> (Float, Float?) {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return (-.infinity, nil) }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let level = 10 * log10(max(sum / Float(n), 1e-12))
        let x = stride(from: 0, to: n, by: step).map { data[$0] }
        let lags = Int(rate / 1000)...Int(rate / 80)
        guard x.count > lags.upperBound * 2 else { return (level, nil) }
        let energy = x.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return (level, nil) }
        var best: (lag: Int, r: Float) = (0, 0)
        for lag in lags {
            var r: Float = 0
            for i in 0..<(x.count - lag) { r += x[i] * x[i + lag] }
            if r > best.r { best = (lag, r) }
        }
        // Voiced: the best lag repeats the buffer well.
        return (level, best.lag > 0 && best.r / energy > 0.5 ? Float(rate) / Float(best.lag) : nil)
    }
}
