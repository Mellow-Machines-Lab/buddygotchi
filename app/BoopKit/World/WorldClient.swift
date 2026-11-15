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
        /// The server answered with an error: its status, for a 429 how many
        /// seconds to wait, and the world server's own error code from its
        /// JSON (`unauthorized`), nil from anything else in the way.
        case status(Int, retryAfter: Int?, error: String? = nil)

        /// The world server says it doesn't know this buddy's key: it was
        /// forgotten (30 days unseen) or left elsewhere. Only its own 401,
        /// never a proxy's or a missing deployment's.
        public var forgotten: Bool {
            if case .status(401, _, "unauthorized") = self { true } else { false }
        }
        /// No answer: offline, a timeout, a name that won't resolve.
        case network(String)
        case unreadable
    }

    struct ServerError: Decodable { var error: String }

    func call<T: Decodable>(_ method: String, _ path: String, key: String? = nil, body: Encodable? = nil, as: T.Type,
                            _ done: @escaping (Result<T, Failure>) -> Void) {
        session.dataTask(with: request(method, path, key: key, body: body)) { [queue] data, response, error in
            let result = Self.result(T.self, data, response, error)
            queue.async { done(result) }
        }.resume()
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], key: String?, body: Encodable?) -> URLRequest {
        var url = base.appendingPathComponent(path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    static func result<T: Decodable>(_: T.Type, _ data: Data?, _ response: URLResponse?, _ error: Error?) -> Result<T, Failure> {
        if let error { return .failure(.network(error.localizedDescription)) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return .failure(.status(http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) },
                                    error: data.flatMap { try? JSONDecoder().decode(ServerError.self, from: $0) }?.error))
        }
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else { return .failure(.unreadable) }
        return .success(value)
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

    /// The same, waiting at most `timeout` seconds on this thread, for the
    /// app's quit: whether it went. The server keeps the gestures waiting
    /// for the next launch, as the app won't live to play them.
    public func sendNow(_ state: World.State, key: String, timeout: TimeInterval) -> Bool {
        // The semaphore orders the answer's write before the read here.
        final class Went: @unchecked Sendable { var value = false }
        let done = DispatchSemaphore(value: 0), went = Went()
        session.dataTask(with: request("PUT", "v1/buddies/me", query: [URLQueryItem(name: "keep_gestures", value: "1")], key: key,
                                     body: state)) { data, response, error in
            if case .success = Self.result(World.Reply.self, data, response, error) { went.value = true }
            done.signal()
        }.resume()
        return done.wait(timeout: .now() + timeout) == .success && went.value
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
