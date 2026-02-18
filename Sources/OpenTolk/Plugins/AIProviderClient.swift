import Foundation

// MARK: - Stream Events

enum StreamEvent {
    case textDelta(String)
    case done(fullText: String)
}

// MARK: - AI Provider Protocol

protocol AIProviderClient {
    func chat(messages: [ChatMessage], model: String?, temperature: Double?,
              maxTokens: Int?) async throws -> String
    func chatStream(messages: [ChatMessage], model: String?, temperature: Double?,
                    maxTokens: Int?) -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - Errors

enum AIProviderError: LocalizedError {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No AI API key configured. Add your OpenAI or Anthropic API key in Settings."
        case .httpError(let code, let body): return "AI request failed (HTTP \(code)): \(body)"
        case .invalidResponse: return "Invalid response from AI provider"
        }
    }
}

// MARK: - Direct AI Client (user's own API key)

final class DirectAIClient: AIProviderClient {
    private let apiKey: String
    private let provider: AIProvider

    enum AIProvider: String {
        case openai
        case anthropic
    }

    init(apiKey: String, provider: AIProvider) {
        self.apiKey = apiKey
        self.provider = provider
    }

    func chat(messages: [ChatMessage], model: String?, temperature: Double?,
              maxTokens: Int?) async throws -> String {
        switch provider {
        case .openai:
            return try await chatOpenAI(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens)
        case .anthropic:
            return try await chatAnthropic(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens)
        }
    }

    func chatStream(messages: [ChatMessage], model: String?, temperature: Double?,
                    maxTokens: Int?) -> AsyncThrowingStream<StreamEvent, Error> {
        switch provider {
        case .openai:
            return chatStreamOpenAI(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens)
        case .anthropic:
            return chatStreamAnthropic(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens)
        }
    }

    // MARK: - OpenAI

    private func chatOpenAI(messages: [ChatMessage], model: String?, temperature: Double?,
                            maxTokens: Int?) async throws -> String {
        var body: [String: Any] = [
            "model": model ?? "gpt-4o-mini",
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.httpError(statusCode: statusCode, body: String(body.prefix(500)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return content
    }

    private func chatStreamOpenAI(messages: [ChatMessage], model: String?, temperature: Double?,
                                  maxTokens: Int?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var body: [String: Any] = [
                        "model": model ?? "gpt-4o-mini",
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true
                    ]
                    if let temperature { body["temperature"] = temperature }
                    if let maxTokens { body["max_tokens"] = maxTokens }

                    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                          (200...299).contains(statusCode) else {
                        continuation.finish(throwing: AIProviderError.httpError(
                            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: "Stream failed"))
                        return
                    }

                    var fullText = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }

                        fullText += content
                        continuation.yield(.textDelta(content))
                    }

                    continuation.yield(.done(fullText: fullText))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Anthropic

    private func chatAnthropic(messages: [ChatMessage], model: String?, temperature: Double?,
                               maxTokens: Int?) async throws -> String {
        let systemMessage = messages.first(where: { $0.role == "system" })?.content
        let nonSystemMessages = messages.filter { $0.role != "system" }

        var body: [String: Any] = [
            "model": model ?? "claude-sonnet-4-20250514",
            "max_tokens": maxTokens ?? 4096,
            "messages": nonSystemMessages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let systemMessage { body["system"] = systemMessage }
        if let temperature { body["temperature"] = temperature }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.httpError(statusCode: statusCode, body: String(body.prefix(500)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    private func chatStreamAnthropic(messages: [ChatMessage], model: String?, temperature: Double?,
                                     maxTokens: Int?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let systemMessage = messages.first(where: { $0.role == "system" })?.content
                    let nonSystemMessages = messages.filter { $0.role != "system" }

                    var body: [String: Any] = [
                        "model": model ?? "claude-sonnet-4-20250514",
                        "max_tokens": maxTokens ?? 4096,
                        "messages": nonSystemMessages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true
                    ]
                    if let systemMessage { body["system"] = systemMessage }
                    if let temperature { body["temperature"] = temperature }

                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                          (200...299).contains(statusCode) else {
                        continuation.finish(throwing: AIProviderError.httpError(
                            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: "Stream failed"))
                        return
                    }

                    var fullText = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        let eventType = json["type"] as? String
                        if eventType == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            fullText += text
                            continuation.yield(.textDelta(text))
                        } else if eventType == "message_stop" {
                            break
                        }
                    }

                    continuation.yield(.done(fullText: fullText))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - AI Client Factory

enum AIClientFactory {
    /// Creates an AI client using the user's configured API key from Settings.
    /// Returns nil if no API key is configured.
    static func makeClient() -> AIProviderClient? {
        guard let apiKey = Config.shared.aiAPIKey, !apiKey.isEmpty else {
            return nil
        }
        let provider: DirectAIClient.AIProvider = Config.shared.aiProvider == "anthropic" ? .anthropic : .openai
        return DirectAIClient(apiKey: apiKey, provider: provider)
    }
}
