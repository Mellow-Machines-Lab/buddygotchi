import AVFoundation
import BoopKit
import Foundation
@preconcurrency import Speech

/// Push-to-talk on the Mac's mic. The core says when:
/// `start` on `talk_on` or the mic button, `stop` on release, the button
/// again, the 30 s limit or a dropped link. The words come back once, and
/// the audio is never kept. Recognition runs on the Mac only.
final class SpeechListener: @unchecked Sendable {
    /// A fresh engine for each recording (`Mic.open`).
    var engine: AVAudioEngine?
    let recognizer = SFSpeechRecognizer()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var best = ""
    var finish: ((String?) -> Void)?
    /// Between `start` and `stop`: whether the mic should be on.
    var wanted = false
    /// Counts recordings, so a late result or timer from one that's over
    /// can't touch the next.
    var session = 0
    let log: (String) -> Void
    let queue = DispatchQueue(label: "boop.talk")

    init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// Turns the mic on, asking for access first if it's the first time.
    /// `failed` gets why, if it can't. If `stop` comes first, while macOS is
    /// still asking, the mic never turns on.
    func start(failed: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            wanted = true
            Mic.authorize { why in
                self.queue.async {
                    guard self.wanted else { return }
                    if let why {
                        self.wanted = false
                        failed(why)
                    } else if let why = self.begin() {
                        self.wanted = false
                        failed(why)
                    }
                }
            }
        }
    }

    /// On `queue`: starts the mic and recognition, or says why it can't.
    private func begin() -> String? {
        if task != nil {
            guard finish != nil else { return nil }  // already listening
            done()  // the last recording is still finishing: hand its words over now
        }
        let request = Mic.request()
        do throws(Mic.Refused) {
            let recognizer = try Mic.onDevice(recognizer)
            // The samples go only to the recognizer.
            engine = try Mic.open(bufferSize: 1024, log: { log("talk: \($0)") }) { _ in { buffer, _ in request.append(buffer) } }
            self.request = request
            best = ""
            session += 1
            let this = session
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                self.queue.async {
                    guard self.session == this else { return }
                    if let result { self.best = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.done() }
                }
            }
            return nil
        } catch {
            return error.why
        }
    }

    /// Stops the mic and hands over what was heard, or nil if nothing was.
    func stop(_ finish: @escaping (String?) -> Void) {
        queue.async { [self] in
            wanted = false
            guard task != nil else {
                finish(nil)
                return
            }
            self.finish = finish
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
            engine = nil
            request?.endAudio()
            // The final result usually arrives within a second.
            let this = session
            queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.session == this else { return }
                self.done()
            }
        }
    }

    func done() {
        guard let finish else { return }
        self.finish = nil
        task?.cancel()
        task = nil
        request = nil
        let words = best.trimmingCharacters(in: .whitespacesAndNewlines)
        best = ""
        finish(words.isEmpty ? nil : words)
    }
}

/// The Mac's mic and its on-device recogniser, as push-to-talk and Boop's
/// ears both open them.
enum Mic {
    /// Why the mic can't listen, as the person reads it.
    struct Refused: Error {
        let why: String
    }

        /// Asks for speech recognition, then the microphone, the first time
        /// either is needed. `done` gets nil when both are allowed,
        /// otherwise why not. Any queue.
        static func authorize(_ done: @escaping @Sendable (String?) -> Void) {
            let refused = "Allow Boop in System Settings → Privacy & Security → "
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                break
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { _ in authorize(done) }
                return
            default:
                done(refused + "Speech Recognition.")
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                done(nil)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { _ in authorize(done) }
            default:
                done(refused + "Microphone.")
            }
        }

    /// `recognizer`, if it runs on this Mac.
    static func onDevice(_ recognizer: SFSpeechRecognizer?) throws(Refused) -> SFSpeechRecognizer {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw Refused(why: "On-device speech recognition isn't available on this Mac.")
        }
        return recognizer
    }

    /// A fresh engine, so it uses the input device of the moment (AirPods
    /// that joined since, a mic unplugged), started with its input tapped by
    /// what `tap` makes for the input's format. `log` gets a failure's
    /// details.
    static func open(bufferSize: AVAudioFrameCount, log: (String) -> Void,
                     tap: (AVAudioFormat) -> AVAudioNodeTapBlock) throws(Refused) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // With no usable input device (a Mac mini with no mic, a closed
        // MacBook) the format is 0 Hz or 0 channels, and a tap on it raises
        // an exception Swift can't catch.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log("no usable input device (\(format.sampleRate) Hz, \(format.channelCount) channels)")
            throw Refused(why: "No microphone is connected.")
        }
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tap(format))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            log("can't start the mic: \(error)")
            throw Refused(why: "The Mac's microphone couldn't start.")
        }
        return engine
    }

    /// A recognition request that stays on the Mac and reports as it goes,
    /// told to expect `phrases`.
    static func request(expecting phrases: [String] = []) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = phrases
        return request
    }
}
