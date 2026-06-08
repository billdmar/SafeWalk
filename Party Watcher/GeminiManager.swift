import Foundation

/// A lightweight singleton wrapper around the Google Gemini REST API.
///
/// `GeminiManager` encodes a multi-turn conversation into Gemini's
/// `generateContent` request shape, performs the network call on
/// `URLSession.shared`, and returns the model's reply text (or `nil` on
/// any failure). Verbose request/response logging is compiled in only for
/// `DEBUG` builds so that response bodies never reach release logs.
class GeminiManager {
    /// Shared instance used throughout the app.
    static let shared = GeminiManager()
    // Loaded from Secrets.swift, which is gitignored. See Secrets.example.swift.
    private let apiKey = Secrets.geminiAPIKey
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

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

    /// Sends a conversation to Gemini and returns the model's reply.
    /// - Parameters:
    ///   - messages: The full conversation so far, oldest first.
    ///   - completion: Called with the trimmed reply text, or `nil` if the
    ///     request fails, the response cannot be decoded, or no candidate is
    ///     returned. Invoked on a background queue.
    func sendMessage(messages: [GeminiMessage], completion: @escaping (String?) -> Void) {
        let requestBody = GeminiRequest(contents: messages)
        guard let url = URL(string: endpoint),
              let httpBody = try? JSONEncoder().encode(requestBody) else {
            #if DEBUG
            print("[GeminiManager] Invalid URL or body")
            #endif
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.httpBody = httpBody

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                print("[GeminiManager] Network error: \(error)")
                #endif
                completion(nil)
                return
            }
            #if DEBUG
            if let httpResponse = response as? HTTPURLResponse {
                print("[GeminiManager] HTTP status: \(httpResponse.statusCode)")
            }
            if let data = data, let bodyString = String(data: data, encoding: .utf8) {
                print("[GeminiManager] Response body: \n\(bodyString)")
            }
            #endif
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                  let reply = decoded.candidates.first?.content.parts.first?.text else {
                completion(nil)
                return
            }
            completion(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        task.resume()
    }
} 