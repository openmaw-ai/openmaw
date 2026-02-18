import Foundation

final class OpenAITranscriber: TranscriptionProvider {
    let providerType: TranscriptionProviderType = .openai
    private let session = URLSession.shared

    func transcribe(audio: RecordedAudio) async throws -> TranscriptionResult {
        guard let apiKey = KeychainHelper.load(key: "openai_api_key"), !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = Data.buildMultipartBody(
            boundary: boundary,
            audioData: audio.data,
            fields: [
                ("model", "whisper-1"),
                ("language", Config.shared.language),
                ("response_format", "text"),
            ],
            filename: audio.filename,
            contentType: audio.contentType
        )
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return TranscriptionResult(text: text, wordsUsed: nil, wordsRemaining: nil)
    }
}
