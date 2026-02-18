import Foundation

enum TranscriberFactory {
    static func makeProvider() -> TranscriptionProvider {
        return makeProvider(for: Config.shared.selectedProvider)
    }

    static func makeProvider(for type: TranscriptionProviderType) -> TranscriptionProvider {
        switch type {
        case .cloud:
            return CloudTranscriber()
        case .groq:
            let apiKey = KeychainHelper.load(key: "groq_api_key") ?? ""
            return GroqTranscriber(apiKey: apiKey)
        case .openai:
            return OpenAITranscriber()
        case .local:
            return LocalTranscriber()
        }
    }
}
