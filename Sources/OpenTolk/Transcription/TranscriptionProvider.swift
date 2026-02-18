import Foundation

enum TranscriptionProviderType: String, CaseIterable, Codable {
    case cloud = "cloud"
    case groq = "groq"
    case openai = "openai"
    case local = "local"

    var displayName: String {
        switch self {
        case .cloud: return "OpenTolk Cloud"
        case .groq: return "Groq (Own Key)"
        case .openai: return "OpenAI (Own Key)"
        case .local: return "Local (On-Device)"
        }
    }

    var isOwnKey: Bool {
        return self == .groq || self == .openai
    }

    var hasUnlimitedFeatures: Bool {
        return self != .cloud
    }
}

protocol TranscriptionProvider {
    var providerType: TranscriptionProviderType { get }
    func transcribe(audio: RecordedAudio) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let wordsUsed: Int?
    let wordsRemaining: Int?
}

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case noData
    case apiError(statusCode: Int, message: String)
    case noAPIKey
    case notAvailable
    case freeTierLimitReached(wordsUsed: Int)
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from transcription API"
        case .noData: return "No data received from transcription API"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .noAPIKey: return "No API key configured"
        case .notAvailable: return "This transcription provider is not yet available"
        case .freeTierLimitReached(let used): return "Free tier limit reached (\(used) words used)"
        case .signInRequired: return "Sign in required to use cloud transcription"
        }
    }
}

extension Notification.Name {
    static let transcriptionProviderChanged = Notification.Name("transcriptionProviderChanged")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
