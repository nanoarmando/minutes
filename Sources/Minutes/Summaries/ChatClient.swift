// resolveEndpointURL is adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/MuesliNativeApp/MeetingSummaryClient.swift
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

import Foundation

/// One OpenAI-compatible endpoint (OpenAI, DeepSeek, Ollama's /v1, Groq…): base URL, optional key and model.
struct ProviderEndpoint: Sendable {
    var baseURL: String
    var apiKey: String?
    var model: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Accepts a bare host, a base ending in /v1 or a complete endpoint URL, and returns the endpoint URL.
    func url(for endpointSuffix: String) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme != nil, components.host != nil else { return nil }
        let suffix = endpointSuffix.split(separator: "/").map(String.init)
        var path = components.path.split(separator: "/").map(String.init)
        if path.isEmpty {
            path = suffix
        } else if path.last == suffix.first {
            path = path.dropLast() + suffix
        } else if !path.suffix(suffix.count).elementsEqual(suffix) {
            path += suffix
        }
        components.path = "/" + path.joined(separator: "/")
        return components.url
    }

    func request(for endpointSuffix: String, timeout: TimeInterval) throws -> URLRequest {
        guard isConfigured else { throw ProviderError.notConfigured }
        guard let url = url(for: endpointSuffix) else { throw ProviderError.invalidURL(baseURL) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

enum ProviderError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case http(status: Int, message: String)
    case emptyResponse
    case outOfTokens

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No provider is configured."
        case .invalidURL(let url): "The base URL “\(url)” is not valid."
        case .http(let status, let message): "The provider returned \(status): \(message)"
        case .emptyResponse: "The provider returned an empty response."
        case .outOfTokens: "The model used its whole token budget before answering. It is probably a reasoning model: turn off its thinking mode or choose a non-reasoning model."
        }
    }

    /// Timeouts, rate limits and server errors are worth retrying; authentication and request errors are not.
    var isRetryable: Bool {
        if case .http(let status, _) = self { return status == 408 || status == 429 || status >= 500 }
        return false
    }
}

enum ProviderHTTP {
    /// Performs the request, retrying up to three times with exponential backoff (1 s, 2 s, 4 s).
    static func send(_ request: URLRequest, retries: Int = 3) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await sendOnce(request)
            } catch {
                let retryable = (error as? ProviderError)?.isRetryable ?? (error is URLError)
                guard retryable, attempt < retries, !Task.isCancelled else { throw error }
                try await Task.sleep(for: .seconds(1 << attempt))
                attempt += 1
            }
        }
    }

    private static func sendOnce(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status: status, message: errorMessage(from: data))
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = (json?["error"] ?? json?["message"]) as? String { return message }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }
}

/// Chat completions against any OpenAI-compatible provider, non-streaming.
struct ChatClient: Sendable {
    let endpoint: ProviderEndpoint
    var timeout: TimeInterval = 300
    var retries = 3

    /// `reasoning` turns on the provider's thinking mode where one exists (DeepSeek); other providers ignore it.
    func complete(system: String, user: String, maxTokens: Int? = 2500, reasoning: Bool = false) async throws -> String {
        var request = try endpoint.request(for: "chat/completions", timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Newer OpenAI models reject max_tokens; other providers only know max_tokens.
        let tokenKey = request.url?.host == "api.openai.com" ? "max_completion_tokens" : "max_tokens"
        var body: [String: Any] = [
            "model": endpoint.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        // Summaries pass nil: the reasoning counts against the limit and can use all of it.
        if let maxTokens { body[tokenKey] = maxTokens }
        // DeepSeek models think by default; outside summaries the reasoning would only cost time and tokens.
        if request.url?.host == "api.deepseek.com" {
            body["thinking"] = ["type": reasoning ? "enabled" : "disabled"]
            if reasoning { body["reasoning_effort"] = "medium" }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await ProviderHTTP.send(request, retries: retries)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let choice = response.choices.first
        let text = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw choice?.finishReason == "length" ? ProviderError.outOfTokens : ProviderError.emptyResponse
        }
        return Self.strippingReasoning(text)
    }

    /// Decodes the first JSON object in a model reply, tolerating code fences and surrounding prose.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from reply: String) -> T? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(type, from: Data(reply[start...end].utf8))
    }

    /// Some local reasoning models (Qwen, DeepSeek R1 on Ollama) prefix their answer with a <think> block.
    private static func strippingReasoning(_ text: String) -> String {
        guard text.hasPrefix("<think>"), let end = text.range(of: "</think>") else { return text }
        return text[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }
}
