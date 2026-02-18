import Foundation

// MARK: - Stream Events

enum StreamEvent {
    case textDelta(String)
    case done(fullText: String)
}

// MARK: - AI Chat Response

/// Unified response from a chat call — either final text or tool calls that need execution.
enum AIChatResponse {
    case text(String)
    case toolCalls([AIToolCall])
}

struct AIToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]
}

/// A message with richer content for tool-call conversations.
/// Wraps ChatMessage but can carry tool_calls and tool results.
struct AIMessage {
    enum Role: String {
        case system, user, assistant, tool
    }

    let role: Role
    let content: String?
    let toolCalls: [AIToolCall]?
    let toolCallID: String?  // for role=tool responses
}

// MARK: - Tool Definition (sent to the API)

struct AIToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]  // JSON Schema
}

// MARK: - AI Provider Protocol

protocol AIProviderClient {
    /// Simple chat — returns text only, ignores tool calls.
    func chat(messages: [ChatMessage], model: String?, temperature: Double?,
              maxTokens: Int?) async throws -> String

    /// Chat with tool support — returns text or tool calls.
    func chatWithTools(messages: [AIMessage], tools: [AIToolDefinition], model: String?,
                       temperature: Double?, maxTokens: Int?) async throws -> AIChatResponse

    /// Streaming chat (no tool support — tools use non-streaming loop).
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

    func chatWithTools(messages: [AIMessage], tools: [AIToolDefinition], model: String?,
                       temperature: Double?, maxTokens: Int?) async throws -> AIChatResponse {
        switch provider {
        case .openai:
            return try await chatWithToolsOpenAI(messages: messages, tools: tools, model: model, temperature: temperature, maxTokens: maxTokens)
        case .anthropic:
            return try await chatWithToolsAnthropic(messages: messages, tools: tools, model: model, temperature: temperature, maxTokens: maxTokens)
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

    // MARK: - OpenAI Simple Chat

    private func chatOpenAI(messages: [ChatMessage], model: String?, temperature: Double?,
                            maxTokens: Int?) async throws -> String {
        var body: [String: Any] = [
            "model": model ?? "gpt-4o-mini",
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }

        let data = try await makeOpenAIRequest(body: body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return content
    }

    // MARK: - OpenAI Chat with Tools

    private func chatWithToolsOpenAI(messages: [AIMessage], tools: [AIToolDefinition], model: String?,
                                     temperature: Double?, maxTokens: Int?) async throws -> AIChatResponse {
        var body: [String: Any] = [
            "model": model ?? "gpt-4o-mini",
            "messages": messages.map { openAIMessage($0) }
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters
                    ]
                ]
            }
        }

        let data = try await makeOpenAIRequest(body: body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        // Check for tool calls
        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            let parsed = toolCalls.compactMap { tc -> AIToolCall? in
                guard let id = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let argsString = function["arguments"] as? String,
                      let argsData = argsString.data(using: .utf8),
                      let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else { return nil }
                return AIToolCall(id: id, name: name, arguments: args)
            }
            if !parsed.isEmpty {
                return .toolCalls(parsed)
            }
        }

        // Regular text response
        let content = message["content"] as? String ?? ""
        return .text(content)
    }

    private func openAIMessage(_ msg: AIMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": msg.role.rawValue]

        if let content = msg.content {
            dict["content"] = content
        }

        if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments)) ?? Data()
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                return [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": argsString
                    ]
                ]
            }
        }

        if let toolCallID = msg.toolCallID {
            dict["tool_call_id"] = toolCallID
        }

        return dict
    }

    private func makeOpenAIRequest(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.httpError(statusCode: statusCode, body: String(responseBody.prefix(500)))
        }
        return data
    }

    // MARK: - OpenAI Streaming (no tools)

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

    // MARK: - Anthropic Simple Chat

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

        let data = try await makeAnthropicRequest(body: body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    // MARK: - Anthropic Chat with Tools

    private func chatWithToolsAnthropic(messages: [AIMessage], tools: [AIToolDefinition], model: String?,
                                        temperature: Double?, maxTokens: Int?) async throws -> AIChatResponse {
        let systemMessage = messages.first(where: { $0.role == .system })?.content
        let nonSystemMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": model ?? "claude-sonnet-4-20250514",
            "max_tokens": maxTokens ?? 4096,
            "messages": nonSystemMessages.map { anthropicMessage($0) }
        ]
        if let systemMessage { body["system"] = systemMessage }
        if let temperature { body["temperature"] = temperature }

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters
                ]
            }
        }

        let data = try await makeAnthropicRequest(body: body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse
        }

        // Check for tool_use blocks
        let toolUseBlocks = contentBlocks.filter { ($0["type"] as? String) == "tool_use" }
        if !toolUseBlocks.isEmpty {
            let parsed = toolUseBlocks.compactMap { block -> AIToolCall? in
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any] else { return nil }
                return AIToolCall(id: id, name: name, arguments: input)
            }
            if !parsed.isEmpty {
                return .toolCalls(parsed)
            }
        }

        // Regular text response
        let textBlocks = contentBlocks.filter { ($0["type"] as? String) == "text" }
        let text = textBlocks.compactMap { $0["text"] as? String }.joined()
        return .text(text)
    }

    private func anthropicMessage(_ msg: AIMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": msg.role.rawValue]

        if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
            // Assistant message with tool_use blocks
            var contentBlocks: [[String: Any]] = []
            if let text = msg.content, !text.isEmpty {
                contentBlocks.append(["type": "text", "text": text])
            }
            for tc in toolCalls {
                contentBlocks.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": tc.arguments
                ])
            }
            dict["content"] = contentBlocks
        } else if msg.role == .tool {
            // Tool result — Anthropic uses role "user" with tool_result content
            dict["role"] = "user"
            dict["content"] = [
                [
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallID ?? "",
                    "content": msg.content ?? ""
                ]
            ]
        } else {
            dict["content"] = msg.content ?? ""
        }

        return dict
    }

    private func makeAnthropicRequest(body: [String: Any]) async throws -> Data {
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
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.httpError(statusCode: statusCode, body: String(responseBody.prefix(500)))
        }
        return data
    }

    // MARK: - Anthropic Streaming (no tools)

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
    static func makeClient() -> AIProviderClient? {
        guard let apiKey = Config.shared.aiAPIKey, !apiKey.isEmpty else {
            return nil
        }
        let provider: DirectAIClient.AIProvider = Config.shared.aiProvider == "anthropic" ? .anthropic : .openai
        return DirectAIClient(apiKey: apiKey, provider: provider)
    }
}
