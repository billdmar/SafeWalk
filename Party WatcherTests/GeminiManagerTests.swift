//
//  GeminiManagerTests.swift
//  Party WatcherTests
//
//  Covers the pure, network-free classification and retry-decision logic
//  extracted from GeminiManager. No real network calls are made.
//

import Testing
import Foundation
@testable import Party_Watcher

struct GeminiManagerTests {

    // MARK: - HTTP status classification

    /// 2xx responses are successes, so classification returns `nil`.
    @Test func successStatusesClassifyAsNil() {
        #expect(GeminiManager.classify(status: 200) == nil)
        #expect(GeminiManager.classify(status: 201) == nil)
        #expect(GeminiManager.classify(status: 299) == nil)
    }

    /// Any non-2xx status maps to a `.server` error value.
    @Test func nonSuccessStatusesClassifyAsServerError() {
        #expect(GeminiManager.classify(status: 400) == .server)
        #expect(GeminiManager.classify(status: 429) == .server)
        #expect(GeminiManager.classify(status: 500) == .server)
        #expect(GeminiManager.classify(status: 503) == .server)
    }

    // MARK: - Retry decision (HTTP status)

    /// 5xx server errors and 429 rate limiting are transient and retried once.
    @Test func transientStatusesAreRetried() {
        #expect(GeminiManager.shouldRetry(status: 429) == true)
        #expect(GeminiManager.shouldRetry(status: 500) == true)
        #expect(GeminiManager.shouldRetry(status: 502) == true)
        #expect(GeminiManager.shouldRetry(status: 599) == true)
    }

    /// Permanent 4xx errors (other than 429) are not retried — retrying would
    /// just fail the same way and delay the user.
    @Test func permanentClientErrorsAreNotRetried() {
        #expect(GeminiManager.shouldRetry(status: 400) == false)
        #expect(GeminiManager.shouldRetry(status: 401) == false)
        #expect(GeminiManager.shouldRetry(status: 403) == false)
        #expect(GeminiManager.shouldRetry(status: 404) == false)
    }

    /// 2xx successes are never "retried" — there's nothing to retry.
    @Test func successStatusesAreNotRetried() {
        #expect(GeminiManager.shouldRetry(status: 200) == false)
        #expect(GeminiManager.shouldRetry(status: 204) == false)
    }

    // MARK: - Retry decision (URLError)

    /// Connectivity blips and timeouts are transient and worth one retry.
    @Test func transientURLErrorsAreRetried() {
        #expect(GeminiManager.shouldRetry(urlError: .timedOut) == true)
        #expect(GeminiManager.shouldRetry(urlError: .networkConnectionLost) == true)
        #expect(GeminiManager.shouldRetry(urlError: .notConnectedToInternet) == true)
        #expect(GeminiManager.shouldRetry(urlError: .cannotConnectToHost) == true)
        #expect(GeminiManager.shouldRetry(urlError: .dnsLookupFailed) == true)
        #expect(GeminiManager.shouldRetry(urlError: .cannotFindHost) == true)
    }

    /// Permanent client-side URL problems are not retried.
    @Test func permanentURLErrorsAreNotRetried() {
        #expect(GeminiManager.shouldRetry(urlError: .badURL) == false)
        #expect(GeminiManager.shouldRetry(urlError: .unsupportedURL) == false)
        #expect(GeminiManager.shouldRetry(urlError: .userAuthenticationRequired) == false)
    }

    // MARK: - API key guard

    /// An empty or whitespace-only key (the CI default) is not usable, so no
    /// network call should be attempted.
    @Test func emptyAPIKeyIsNotUsable() {
        #expect(GeminiManager.isUsable(apiKey: "") == false)
        #expect(GeminiManager.isUsable(apiKey: "   ") == false)
        #expect(GeminiManager.isUsable(apiKey: "\n\t ") == false)
    }

    /// A non-empty key is treated as usable.
    @Test func nonEmptyAPIKeyIsUsable() {
        #expect(GeminiManager.isUsable(apiKey: "AIzaSyExampleKey") == true)
    }

    // MARK: - Conversation pruning

    private func msg(_ role: String, _ text: String) -> GeminiManager.GeminiMessage {
        .init(role: role, parts: [.init(text: text)])
    }

    /// A short conversation (within the limit) is returned unchanged.
    @Test func pruneLeavesShortConversationsUntouched() {
        let convo = [msg("user", "system prompt"), msg("user", "hi"), msg("model", "hello")]
        let pruned = GeminiManager.prune(convo, keepingLast: 20)
        #expect(pruned.count == 3)
    }

    /// A long conversation keeps the leading system prompt plus the most recent
    /// `keepingLast` turns — bounding what is re-sent on every request.
    @Test func pruneKeepsSystemPromptAndRecentTurns() {
        var convo = [msg("user", "SYSTEM")]
        for i in 0..<50 { convo.append(msg(i.isMultiple(of: 2) ? "user" : "model", "turn \(i)")) }

        let pruned = GeminiManager.prune(convo, keepingLast: 10)

        #expect(pruned.count == 11)                                  // system + 10
        #expect(pruned.first?.parts.first?.text == "SYSTEM")          // system prompt preserved
        #expect(pruned.last?.parts.first?.text == "turn 49")          // newest kept
        #expect(pruned.contains { $0.parts.first?.text == "turn 0" } == false) // oldest dropped
    }
}
