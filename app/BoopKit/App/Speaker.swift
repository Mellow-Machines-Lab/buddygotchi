import AVFoundation
import Foundation

/// Says Boop's sentence (an aside, or a remark) aloud on the Mac, when Settings' Voice speaks
/// (`AppSettings.Voice`): the core decided the words (`Moment.aloud`),
/// this only makes them heard. It never blocks the Moment: the runtime
/// starts it and moves on. Two kinds: this Mac's own voice
/// (`SystemSpeaker`) and a cloud voice (`CloudSpeaker`).
public protocol Speaker: Sendable {
    func speak(_ sentence: String, mood: String) async
}

extension AppSettings.Voice {
    /// What says a sentence for this choice, or nil for the board's own
    /// sounds. With a `folder`, each sentence is written there as a file
    /// instead of played, for checks that mustn't make a sound.
    public func speaker(cloud: CloudSpeaker.Config?, key: @escaping @Sendable () -> String?, folder: URL? = nil) -> (any Speaker)? {
        switch self {
        case .sounds: return nil
        case .speaks: return SystemSpeaker(folder: folder)
        case .cloud:
            let local = SystemSpeaker(folder: folder)
            return CloudSpeaker(config: cloud ?? CloudSpeaker.Config(), key: key, fallback: local,
                                play: folder.map { CloudSpeaker.writer(to: $0) } ?? CloudSpeaker.playAloud)
        }
    }
}

/// This Mac's own voice: the best English voice installed, pitched up and
/// quick so it sounds small and lively, by the face's mood. The one place a
/// better on-device voice would go.
public final class SystemSpeaker: Speaker, @unchecked Sendable {
    let synthesizer = AVSpeechSynthesizer()
    /// Where each sentence is written as a file instead, or nil to play it.
    let folder: URL?
    private let lock = NSLock()
    private var written = 0

    public init(folder: URL? = nil) {
        self.folder = folder
    }

    /// The best installed English voice: premium, then enhanced, then
    /// any, American English first. Nil leaves it to the system.
    public static func voice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            let quality = switch v.quality {
            case .premium: 20
            case .enhanced: 10
            default: 0
            }
            // The novelty voices (Bells, Bubbles, Zarvox…) never.
            let novelty = v.voiceTraits.contains(.isNoveltyVoice) ? -100 : 0
            return quality + (v.language == "en-US" ? 2 : 0) + novelty
        }
        return english.max { score($0) < score($1) }
    }

    /// The pitch (1 is the voice's own) and the rate (of the system's
    /// default) a face's mood speaks in: glad faces higher and quicker,
    /// low ones slower, cross ones clipped.
    public static func tone(mood: String) -> (pitch: Float, rate: Float) {
        switch mood {
        case "happy", "excited", "pleased", "proud", "amused", "affectionate", "mischievous", "surprised": (1.55, 1.12)
        case "sad", "wounded", "lonely": (1.25, 0.9)
        case "annoyed", "grumpy", "angry", "determined", "cross": (1.3, 1.08)
        default: (1.4, 1.04)
        }
    }

    func utterance(_ sentence: String, mood: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: sentence)
        u.voice = Self.voice()
        let (pitch, rate) = Self.tone(mood: mood)
        u.pitchMultiplier = pitch
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        u.preUtteranceDelay = 0
        return u
    }

    public func speak(_ sentence: String, mood: String) async {
        guard let folder else { return synthesizer.speak(utterance(sentence, mood: mood)) }
        let n = lock.withLock {
            written += 1
            return written
        }
        try? await render(sentence, mood: mood, to: folder.appendingPathComponent(String(format: "said-%03d.caf", n)))
    }

    /// Writes `sentence` as `mood` speaks it to an audio file at `url` (its
    /// kind by the extension: `.caf`, `.wav`, `.m4a`), never a sound.
    public func render(_ sentence: String, mood: String, to url: URL) async throws {
        let renderer = AVSpeechSynthesizer()
        let box = FileBox(url)
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            renderer.write(utterance(sentence, mood: mood)) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // An empty buffer is the end.
                guard pcm.frameLength > 0 else { return box.finish(done) }
                box.append(pcm, done)
            }
        }
        _ = renderer
    }

    /// The file a render writes, as its buffers come.
    final class FileBox: @unchecked Sendable {
        let url: URL
        var file: AVAudioFile?
        var finished = false
        let lock = NSLock()
        init(_ url: URL) { self.url = url }

        func append(_ pcm: AVAudioPCMBuffer, _ done: CheckedContinuation<Void, Error>) {
            lock.withLock {
                guard !finished else { return }
                do {
                    if file == nil {
                        var settings = pcm.format.settings
                        if url.pathExtension == "m4a" {
                            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: pcm.format.sampleRate,
                                        AVNumberOfChannelsKey: pcm.format.channelCount]
                        }
                        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: pcm.format.commonFormat,
                                               interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    finished = true
                    done.resume(throwing: error)
                }
            }
        }

        func finish(_ done: CheckedContinuation<Void, Error>) {
            lock.withLock {
                guard !finished else { return }
                finished = true
                file = nil
                done.resume()
            }
        }
    }
}

/// A cloud voice: an OpenAI-style `POST …/audio/speech` on your own key,
/// its audio played on the Mac. Only the sentence's words, the model, the
/// voice and a sentence of how to say them in the face's mood are sent.
/// Too slow (over `deadline`) or failing, this Mac's voice says it
/// instead (`fallback`), so a sentence is never lost to the network.
public final class CloudSpeaker: Speaker, @unchecked Sendable {
    /// Where it asks, with which model and voice (`settings.json`'s
    /// `cloudVoice`): OpenAI's unless set.
    public struct Config: Codable, Equatable, Sendable {
        public var url = "https://api.openai.com/v1"
        public var model = "gpt-4o-mini-tts"
        public var voice = "coral"

        public init(url: String = "https://api.openai.com/v1", model: String = "gpt-4o-mini-tts", voice: String = "coral") {
            self.url = url
            self.model = model
            self.voice = voice
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? url
            model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? model
            voice = (try? c.decodeIfPresent(String.self, forKey: .voice)) ?? voice
        }
    }

    /// The environment variable the key may come from, before the Keychain.
    public static let keyVariable = "BOOP_VOICE_KEY"
    /// The longest it waits for the audio, in seconds.
    public static let deadline: TimeInterval = 1.5

    let config: Config
    let key: @Sendable () -> String?
    let session: URLSession
    let fallback: (any Speaker)?
    let play: @Sendable (Data) async -> Void
    let deadline: TimeInterval

    public init(config: Config = Config(), key: @escaping @Sendable () -> String?, session: URLSession = .shared,
                fallback: (any Speaker)?, deadline: TimeInterval = CloudSpeaker.deadline,
                play: @escaping @Sendable (Data) async -> Void = CloudSpeaker.playAloud) {
        self.config = config
        self.key = key
        self.session = session
        self.fallback = fallback
        self.play = play
        self.deadline = deadline
    }

    /// The key: `BOOP_VOICE_KEY`, else the app's own Keychain item for the
    /// Boop on `stateDir` (`Keychain.voiceKey`). Reads the Keychain, so
    /// never on the main thread or `home`.
    public static func key(stateDir: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let key = environment[keyVariable].map(Keychain.cleaned), !key.isEmpty { return key }
        return Keychain.voiceKey(account: Keychain.account(for: stateDir))
    }

    /// The request for `sentence` in `mood`.
    public func request(_ sentence: String, mood: String, key: String) -> URLRequest? {
        guard let url = URL(string: config.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/audio/speech") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: deadline)
        r.httpMethod = "POST"
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "model": config.model, "voice": config.voice, "input": sentence, "response_format": "mp3",
            "instructions": "You are a small, warm, slightly cheeky desk creature. Say this short and lively, feeling \(mood).",
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return r
    }

    public func speak(_ sentence: String, mood: String) async {
        if let key = key(), let request = request(sentence, mood: mood, key: key), let audio = await fetch(request) {
            return await play(audio)
        }
        await fallback?.speak(sentence, mood: mood)
    }

    /// The audio, or nil on any error, a status that isn't 2xx, or no
    /// answer within `deadline`.
    func fetch(_ request: URLRequest) async -> Data? {
        let session = self.session, deadline = self.deadline
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
                return data
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Plays audio on the Mac's speakers, held until it ends.
    public static let playAloud: @Sendable (Data) async -> Void = { data in
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.play()
        try? await Task.sleep(nanoseconds: UInt64((player.duration + 0.2) * 1_000_000_000))
        player.stop()
    }

    /// Writes each audio it gets into `folder` instead, numbered, for
    /// checks that mustn't make a sound.
    public static func writer(to folder: URL) -> @Sendable (Data) async -> Void {
        let count = Counter()
        return { data in
            try? data.write(to: folder.appendingPathComponent(String(format: "cloud-%03d.mp3", count.next())))
        }
    }

    final class Counter: @unchecked Sendable {
        private var n = 0
        private let lock = NSLock()
        func next() -> Int { lock.withLock { n += 1; return n } }
    }
}
