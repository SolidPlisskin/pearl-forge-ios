import Foundation

/// A failure in one of the cloud calls, worded for the person using the app.
struct PipelineError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Shared request plumbing for the ElevenLabs and Anthropic clients.
enum PipelineHTTP {
    /// Sends the request and returns the body. HTTP errors become a
    /// PipelineError like "Could not list your voices (401): Invalid API key".
    /// `explanations` replaces the service's own message for particular
    /// statuses, such as 402 for a plan that doesn't include a feature.
    static func send(_ request: URLRequest, failure: String,
                     explanations: [Int: String] = [:]) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let explanation = explanations[status] {
            throw PipelineError(message: explanation)
        }
        guard status < 400 else {
            throw PipelineError(message: "\(failure) (\(status)): \(readableMessage(from: data))")
        }
        return data
    }

    /// Pulls the human-readable message out of an API error body, falling back
    /// to the start of the raw body.
    private static func readableMessage(from data: Data) -> String {
        var parsed = try? JSONSerialization.jsonObject(with: data)
        // Gemini sometimes wraps its error in a one-item list.
        if let list = parsed as? [Any], let first = list.first {
            parsed = first
        }
        if let json = parsed as? [String: Any] {
            // Anthropic: {"error": {"message": "..."}}
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            // ElevenLabs: {"detail": {"message": "..."}} or {"detail": "..."}
            if let detail = json["detail"] as? [String: Any], let message = detail["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
        }
        return String(decoding: data.prefix(500), as: UTF8.self)
    }
}

/// A multipart/form-data request body, for uploading the recording.
struct MultipartForm {
    private let boundary = "PearlForge-\(UUID().uuidString)"
    private var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// The finished body, with the closing boundary.
    var body: Data {
        parts + Data("--\(boundary)--\r\n".utf8)
    }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        parts.append(data)
        append("\r\n")
    }

    private mutating func append(_ string: String) {
        parts.append(Data(string.utf8))
    }
}
