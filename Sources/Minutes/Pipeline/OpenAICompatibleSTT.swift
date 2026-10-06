import Foundation

/// Hosted transcription through the OpenAI audio transcription contract: one multipart request per chunk, so
/// each upload stays far below the providers' 25 MB limit. Retries come from `ProviderHTTP`; the fallback to
/// the on-device model and the gap marker are handled by the caller.
struct OpenAICompatibleSTT: TranscriptionEngine {
    let endpoint: ProviderEndpoint

    var identifier: String { endpoint.model }

    func transcribe(_ chunk: URL) async throws -> String {
        let boundary = "minutes-\(UUID().uuidString)"
        var request = try endpoint.request(for: "audio/transcriptions", timeout: 120)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        appendField("model", endpoint.model)
        appendField("response_format", "json")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: chunk))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let data = try await ProviderHTTP.send(request)
        struct Response: Decodable { let text: String }
        return try JSONDecoder().decode(Response.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
