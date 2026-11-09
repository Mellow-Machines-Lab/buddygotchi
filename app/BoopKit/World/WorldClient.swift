import Foundation

/// The world server's HTTP calls (internal/world/README.md's API), each with
/// a timeout, its answer handed to `done` on the queue it's given. It
/// decides nothing: `WorldLink` says when to call.
public final class WorldClient: @unchecked Sendable {
    /// The live server; `BOOP_WORLD_URL` points the app elsewhere.
    public static let defaultURL = URL(string: "https://boop-world-michaeljxzhu.vercel.app")!
    public static let timeout: TimeInterval = 15

    /// The URL the app uses: `BOOP_WORLD_URL`, else the live server.
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        environment["BOOP_WORLD_URL"].flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? defaultURL
    }

    public let base: URL
    let session: URLSession
    let queue: DispatchQueue

    /// `protocols` stand in for the network in tests.
    public init(base: URL, queue: DispatchQueue, protocols: [AnyClass] = []) {
        self.base = base
        self.queue = queue
        let config = URLSessionConfiguration.ephemeral
        if !protocols.isEmpty { config.protocolClasses = protocols }
        config.timeoutIntervalForRequest = Self.timeout
        config.httpAdditionalHeaders = ["User-Agent": "Boop/\(BoopVersion.current)"]
        session = URLSession(configuration: config)
    }

    public enum Failure: Error, Equatable {
        /// The server answered with an error: its status, and for a 429 how
        /// many seconds to wait.
        case status(Int, retryAfter: Int?)
        /// No answer: offline, a timeout, a name that won't resolve.
        case network(String)
        case unreadable
    }

    func call<T: Decodable>(_ method: String, _ path: String, key: String? = nil, body: Encodable? = nil, as: T.Type,
                            _ done: @escaping (Result<T, Failure>) -> Void) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        session.dataTask(with: request) { [queue] data, response, error in
            let result: Result<T, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(.status(http.statusCode, retryAfter: (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }))
            } else if let data, let value = try? JSONDecoder().decode(T.self, from: data) {
                result = .success(value)
            } else {
                result = .failure(.unreadable)
            }
            queue.async { done(result) }
        }.resume()
    }

    struct Join: Encodable {
        var name: String
        var utcOffset: Int
        enum CodingKeys: String, CodingKey { case name, utcOffset = "utc_offset" }
    }

    struct Ok: Decodable { var ok: Bool? }
    struct Gestures: Decodable { var gestures: [World.Gesture] }
    struct Send: Encodable {
        var to: String
        var kind: World.GestureKind
    }

    /// Joins the world as `name`: the buddy's id and key, the key only here.
    public func join(name: String, utcOffset: Int, _ done: @escaping (Result<World.Joined, Failure>) -> Void) {
        call("POST", "v1/buddies", body: Join(name: name, utcOffset: utcOffset), as: World.Joined.self, done)
    }

    /// The buddy's state and what it added since its last send; the reply
    /// carries the gestures waiting.
    public func send(_ state: World.State, key: String, _ done: @escaping (Result<World.Reply, Failure>) -> Void) {
        call("PUT", "v1/buddies/me", key: key, body: state, as: World.Reply.self, done)
    }

    /// Leaves the world: the buddy's row, days and gestures go.
    public func leave(key: String, _ done: @escaping (Result<Void, Failure>) -> Void) {
        call("DELETE", "v1/buddies/me", key: key, as: Ok.self) { done($0.map { _ in () }) }
    }

    public func world(_ done: @escaping (Result<World.Snapshot, Failure>) -> Void) {
        call("GET", "v1/world", as: World.Snapshot.self, done)
    }

    public func gestures(key: String, _ done: @escaping (Result<[World.Gesture], Failure>) -> Void) {
        call("GET", "v1/gestures", key: key, as: Gestures.self) { done($0.map(\.gestures)) }
    }

    public func gesture(_ kind: World.GestureKind, to buddy: String, key: String, _ done: @escaping (Result<Void, Failure>) -> Void) {
        call("POST", "v1/gestures", key: key, body: Send(to: buddy, kind: kind), as: Ok.self) { done($0.map { _ in () }) }
    }
}
