//
//  GeminiManagerIntegrationTests.swift
//  Party WatcherTests
//
//  Exercises GeminiManager's real request/decode/retry pipeline end-to-end
//  without touching the network, by injecting a URLSession backed by a
//  URLProtocol stub. This complements the pure-classification tests: it proves
//  the actual `send` path encodes the request, decodes a real Gemini response,
//  retries once on a transient 500, and fails fast on a permanent 400.
//

import Testing
import Foundation
@testable import Party_Watcher

/// A `URLProtocol` that returns scripted responses, one per request, so a test
/// can drive multi-attempt (retry) flows deterministically.
final class StubURLProtocol: URLProtocol {
    /// Each element is one attempt's outcome: (status, body) or an error.
    nonisolated(unsafe) static var responses: [Result<(status: Int, body: Data), Error>] = []
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        responses = []
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let index = Self.requestCount
        Self.requestCount += 1
        let outcome = index < Self.responses.count ? Self.responses[index] : Self.responses.last

        switch outcome {
        case .success(let (status, body)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .none:
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }
}

/// Serialized because the tests share `StubURLProtocol`'s static script + the
/// process-wide URL loading system; running them in parallel would interleave
/// their scripted responses.
@Suite(.serialized)
struct GeminiManagerIntegrationTests {

    private func makeManager() -> GeminiManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        // Near-zero retry delay keeps the retry test fast.
        return GeminiManager(apiKey: "TEST_KEY", session: session, retryDelay: 0.01)
    }

    private func successBody(_ text: String) -> Data {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"\(text)"}]}}]}
        """
        return Data(json.utf8)
    }

    private let convo: [GeminiManager.GeminiMessage] = [
        .init(role: "user", parts: [.init(text: "hi")])
    ]

    @Test func successfulResponseDecodesReplyText() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [.success((200, successBody("I'm here with you.")))]
        let manager = makeManager()

        let reply: String? = await withCheckedContinuation { cont in
            manager.send(messages: convo) { result in
                cont.resume(returning: try? result.get())
            }
        }
        #expect(reply == "I'm here with you.")
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func transient500IsRetriedThenSucceeds() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [
            .success((500, Data())),                       // first attempt: transient
            .success((200, successBody("recovered")))      // retry succeeds
        ]
        let manager = makeManager()

        let reply: String? = await withCheckedContinuation { cont in
            manager.send(messages: convo) { result in
                cont.resume(returning: try? result.get())
            }
        }
        #expect(reply == "recovered")
        #expect(StubURLProtocol.requestCount == 2)         // proved the retry happened
    }

    @Test func permanent400FailsFastWithoutRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [.success((400, Data()))]
        let manager = makeManager()

        let error: GeminiManager.GeminiError? = await withCheckedContinuation { cont in
            manager.send(messages: convo) { result in
                if case .failure(let err) = result { cont.resume(returning: err) }
                else { cont.resume(returning: nil) }
            }
        }
        #expect(error == .server)
        #expect(StubURLProtocol.requestCount == 1)         // no retry on a permanent 4xx
    }

    @Test func networkTimeoutIsRetriedThenSucceeds() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [
            .failure(URLError(.timedOut)),
            .success((200, successBody("back online")))
        ]
        let manager = makeManager()

        let reply: String? = await withCheckedContinuation { cont in
            manager.send(messages: convo) { result in
                cont.resume(returning: try? result.get())
            }
        }
        #expect(reply == "back online")
        #expect(StubURLProtocol.requestCount == 2)
    }
}
