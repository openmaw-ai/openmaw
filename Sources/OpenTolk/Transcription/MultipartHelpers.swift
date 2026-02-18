import Foundation

extension Data {
    mutating func appendMultipart(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    static func buildMultipartBody(
        boundary: String,
        audioData: Data,
        fields: [(name: String, value: String)],
        filename: String = "audio.m4a",
        contentType: String = "audio/mp4"
    ) -> Data {
        var body = Data()

        // Audio file field
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendMultipart("Content-Type: \(contentType)\r\n\r\n")
        body.append(audioData)
        body.appendMultipart("\r\n")

        // Text fields
        for field in fields {
            body.appendMultipart("--\(boundary)\r\n")
            body.appendMultipart("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.appendMultipart("\(field.value)\r\n")
        }

        body.appendMultipart("--\(boundary)--\r\n")

        return body
    }
}
