import Foundation

/// A lightweight singleton wrapper around the Google Gemini REST API.
///
/// `GeminiManager` encodes a multi-turn conversation into Gemini's
/// `generateContent` request shape, performs the network call on a
/// dedicated `URLSession` with an explicit request timeout, and returns
/// the model's reply text (or `nil` on any failure). On transient failures
/// (network errors, HTTP 5xx, or 429) it automatically retries once after a
/// short delay; permanent 4xx failures are not retried. Verbose
/// request/response logging is compiled in only for `DEBUG` builds so that
/// response bodies and the API key never reach release logs.
class GeminiManager {
    /// Shared instance used throughout the app.
    static let shared = GeminiManager()
    // Loaded from Secrets.swift, which is gitignored. See Secrets.example.swift.
    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    /// Per-request timeout. A hung connection fails fast rather than relying
    /// on `URLSession.shared`'s 60s default, which is far too long for a UI
    /// awaiting a safety check-in reply.
    private let requestTimeout: TimeInterval = 15
    /// Delay before the single automatic retry on a transient failure.
    private let retryDelay: TimeInterval

    /// Session configured with an explicit request timeout.
    private let session: URLSession

    /// Designated initializer. The defaults reproduce the production setup;
    /// tests inject a stub `URLSession` (via a `URLProtocol`), a known API key,
    /// and a near-zero retry delay so the real request/retry pipeline can be
    /// exercised without the network or slow waits.
    init(apiKey: String = Secrets.geminiAPIKey,
         session: URLSession? = nil,
         retryDelay: TimeInterval = 1) {
        self.apiKey = apiKey
        self.retryDelay = retryDelay
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: config)
        }
    }

    struct GeminiPart: Codable {
        let text: String
    }

    struct GeminiMessage: Codable {
        let role: String // "user" or "model"
        let parts: [GeminiPart]
    }

    struct GeminiRequest: Codable {
        let contents: [GeminiMessage]
    }

    struct GeminiResponse: Codable {
        struct Candidate: Codable {
            struct Content: Codable {
                let parts: [GeminiPart]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }

    /// Typed failure modes so the UI can show better copy later instead of a
    /// single opaque `nil`. These are the only ways a request can fail.
    enum GeminiError: Error {
        /// The device could not reach the network or the connection dropped.
        case network
        /// The request exceeded `requestTimeout`.
        case timeout
        /// The server returned a retryable error (HTTP 5xx, or 429).
        case server
        /// The response body could not be decoded into `GeminiResponse`.
        case decoding
        /// The response decoded but contained no candidate reply text.
        case noCandidate
        /// No API key is configured, so no network call was attempted.
        case missingKey
        /// The request could not be built (invalid endpoint URL or the
        /// conversation failed to encode) — a client-side problem, distinct
        /// from a `.decoding` failure parsing the *response*.
        case invalidRequest
    }

    // MARK: - Pure, testable classification logic

    /// Maps an HTTP status code to a `GeminiError`, or `nil` for a success
    /// (2xx) response. Pure and network-free so it can be unit-tested.
    /// - 2xx: success (`nil`).
    /// - 429 / 5xx: `.server` (transient — eligible for retry).
    /// - other 4xx: `.server` as well, but `shouldRetry(status:)` reports
    ///   them as non-retryable so they fail fast.
    static func classify(status: Int) -> GeminiError? {
        if (200...299).contains(status) {
            return nil
        }
        return .server
    }

    /// Whether a request that produced this HTTP status should be retried.
    /// Transient server-side conditions (5xx) and rate limiting (429) are
    /// retried once; all other non-2xx statuses (permanent 4xx such as 400,
    /// 401, 403, 404) are not. Pure and network-free.
    static func shouldRetry(status: Int) -> Bool {
        if status == 429 { return true }
        return (500...599).contains(status)
    }

    /// Whether a `URLError` represents a transient condition worth retrying
    /// (connectivity blips, timeouts, dropped connections) versus a permanent
    /// client-side problem. Pure and network-free.
    static func shouldRetry(urlError code: URLError.Code) -> Bool {
        switch code {
        case .timedOut,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .cannotFindHost:
            return true
        default:
            return false
        }
    }

    /// Whether the configured API key is usable. An empty key (the CI default)
    /// means no network call should be attempted. Pure and network-free.
    static func isUsable(apiKey: String) -> Bool {
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Bounds an ever-growing conversation before it's sent to the API.
    ///
    /// A long walk accumulates many check-in turns; sending the entire history
    /// on every request wastes tokens and latency without improving the reply.
    /// This keeps the leading system-prompt turn (the first message, which sets
    /// the companion's behavior) plus the most recent `keepingLast` turns. Pure
    /// and network-free.
    static func prune(_ messages: [GeminiMessage], keepingLast keep: Int) -> [GeminiMessage] {
        guard messages.count > keep + 1 else { return messages }
        let system = messages.first.map { [$0] } ?? []
        let recent = messages.suffix(keep)
        return system + recent
    }

    // MARK: - Public API

    /// Sends a conversation to Gemini and returns the model's reply.
    ///
    /// Backward-compatible thin wrapper over ``send(messages:completion:)``:
    /// existing callers that expect `(String?) -> Void` keep working, getting
    /// `nil` on any failure mode.
    /// - Parameters:
    ///   - messages: The full conversation so far, oldest first.
    ///   - completion: Called with the trimmed reply text, or `nil` if the
    ///     request fails for any reason. Invoked on a background queue.
    func sendMessage(messages: [GeminiMessage], completion: @escaping (String?) -> Void) {
        send(messages: messages) { result in
            switch result {
            case .success(let reply):
                completion(reply)
            case .failure:
                completion(nil)
            }
        }
    }

    /// Sends a conversation to Gemini, returning a typed result.
    ///
    /// Guards against an empty API key up front (no network call), enforces a
    /// request timeout, and retries once on a transient failure.
    /// - Parameters:
    ///   - messages: The full conversation so far, oldest first.
    ///   - completion: Called with the trimmed reply text or a ``GeminiError``.
    ///     Invoked on a background queue.
    func send(messages: [GeminiMessage], completion: @escaping (Result<String, GeminiError>) -> Void) {
        guard Self.isUsable(apiKey: apiKey) else {
            #if DEBUG
            print("[GeminiManager] Missing API key — skipping network call")
            #endif
            completion(.failure(.missingKey))
            return
        }

        let requestBody = GeminiRequest(contents: messages)
        guard let url = URL(string: endpoint),
              let httpBody = try? JSONEncoder().encode(requestBody) else {
            #if DEBUG
            print("[GeminiManager] Invalid URL or body")
            #endif
            completion(.failure(.invalidRequest))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.httpBody = httpBody

        perform(request: request, allowRetry: true, completion: completion)
    }

    // MARK: - Internal request execution

    /// Performs a single request attempt, scheduling one retry after
    /// `retryDelay` if the failure is transient and `allowRetry` is `true`.
    private func perform(request: URLRequest,
                         allowRetry: Bool,
                         completion: @escaping (Result<String, GeminiError>) -> Void) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(.failure(.network))
                return
            }

            if let error = error {
                let urlCode = (error as? URLError)?.code
                let isTimeout = urlCode == .timedOut
                #if DEBUG
                print("[GeminiManager] Network error: \(error)")
                #endif
                let transient = urlCode.map(Self.shouldRetry(urlError:)) ?? false
                if allowRetry && transient {
                    self.retry(request: request, completion: completion)
                } else {
                    completion(.failure(isTimeout ? .timeout : .network))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("[GeminiManager] HTTP status: \(httpResponse.statusCode)")
                #endif
                if let classified = Self.classify(status: httpResponse.statusCode) {
                    if allowRetry && Self.shouldRetry(status: httpResponse.statusCode) {
                        self.retry(request: request, completion: completion)
                    } else {
                        completion(.failure(classified))
                    }
                    return
                }
            }

            #if DEBUG
            if let data = data, let bodyString = String(data: data, encoding: .utf8) {
                print("[GeminiManager] Response body: \n\(bodyString)")
            }
            #endif

            guard let data = data,
                  let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
                completion(.failure(.decoding))
                return
            }
            guard let reply = decoded.candidates.first?.content.parts.first?.text else {
                completion(.failure(.noCandidate))
                return
            }
            completion(.success(reply.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        task.resume()
    }

    /// Schedules the single retry attempt after `retryDelay`, disabling any
    /// further retries.
    private func retry(request: URLRequest,
                       completion: @escaping (Result<String, GeminiError>) -> Void) {
        #if DEBUG
        print("[GeminiManager] Transient failure — retrying once in \(retryDelay)s")
        #endif
        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self = self else {
                completion(.failure(.network))
                return
            }
            self.perform(request: request, allowRetry: false, completion: completion)
        }
    }
}
