import AVFoundation
import BoopKit
import Foundation
@preconcurrency import Speech

/// Push-to-talk on the Mac's mic. The core says when:
/// `start` on `talk_on` or the mic button, `stop` on release, the button
/// again, the 30 s limit or a dropped link. The words come back once, and
/// the audio is never kept. Recognition runs on the Mac only.
final class SpeechListener: @unchecked Sendable {
    /// A fresh engine for each recording, so it uses the input device of
    /// the moment (AirPods that joined since, a mic unplugged).
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

    /// Asks for speech recognition, then the microphone, the first time
    /// either is needed. `done` gets nil when both are allowed,
    /// otherwise why not. Any queue.
    func authorize(_ done: @escaping @Sendable (String?) -> Void) {
        let refused = "Allow Boop in System Settings → Privacy & Security → "
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { _ in self.authorize(done) }
            return
        default:
            done(refused + "Speech Recognition.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            done(nil)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in self.authorize(done) }
        default:
            done(refused + "Microphone.")
        }
    }

    /// Turns the mic on, asking for access first if it's the first time.
    /// `failed` gets why, if it can't. If `stop` comes first, while macOS is
    /// still asking, the mic never turns on.
    func start(failed: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            wanted = true
            authorize { why in
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
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return "On-device speech recognition isn't available on this Mac."
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // With no usable input device (a Mac mini with no mic, a closed
        // MacBook) the format is 0 Hz or 0 channels, and a tap on it raises
        // an exception Swift can't catch.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log("talk: no usable input device (\(format.sampleRate) Hz, \(format.channelCount) channels)")
            return "No microphone is connected."
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        self.engine = engine
        best = ""
        // The samples go only to the recognizer.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            log("talk: can't start the mic: \(error)")
            input.removeTap(onBus: 0)
            self.request = nil
            self.engine = nil
            return "The Mac's microphone couldn't start."
        }
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
