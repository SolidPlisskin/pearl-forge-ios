import Foundation

/// fal.ai: avatar video models paid per second of video, with no
/// subscription. Pearl Forge uploads the avatar picture and the pearl's audio
/// to fal's storage, queues the video, checks on it, then downloads it.
struct FalClient {
    let apiKey: String

    static let queueBase = URL(string: "https://queue.fal.run")!
    static let restBase = URL(string: "https://rest.fal.ai")!
    static let platformBase = URL(string: "https://api.fal.ai/v1")!

    /// How long fal keeps what Pearl Forge sends and gets back: the uploads
    /// only need to last until the video is made; the finished video waits
    /// long enough to be collected after a lost connection.
    static let uploadLifetime = 86_400
    static let videoLifetime = 604_800

    private static let badKeyMessage = "fal.ai didn't accept your key. Check it in Settings › API keys."

    /// Your fal.ai balance in dollars, or nil when the key may only make
    /// videos and not read billing (fal's "API" key preset). Throws when fal
    /// doesn't accept the key, so this doubles as the key check.
    func balance() async throws -> Double? {
        var components = URLComponents(url: Self.platformBase.appending(path: "account/billing"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "expand", value: "credits")]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            struct Response: Decodable {
                struct Credits: Decodable {
                    let currentBalance: Double

                    enum CodingKeys: String, CodingKey {
                        case currentBalance = "current_balance"
                    }
                }
                let credits: Credits?
            }
            return try? JSONDecoder().decode(Response.self, from: data).credits?.currentBalance
        case 401:
            throw PipelineError(message: Self.badKeyMessage)
        case 403:
            // A working key that isn't allowed to read billing.
            return nil
        case let status:
            throw PipelineError(message: "Couldn't reach fal.ai (\(status)): \(PipelineHTTP.readableMessage(from: data))")
        }
    }

    /// Uploads the picture and audio, queues a video of the picture speaking
    /// the audio, and returns its request id for checkVideo.
    func startVideo(_ model: VideoModel, picture: Data, audio: Data, audioExtension: String) async throws -> String {
        guard let endpoint = model.falEndpoint else {
            throw PipelineError(message: "\(model.name) isn't a fal.ai model.")
        }
        let imageURL = try await upload(picture, contentType: "image/jpeg", fileName: "avatar.jpg")
        let ext = audioExtension.lowercased()
        let audioURL = try await upload(audio, contentType: Self.audioContentType(ext), fileName: "pearl.\(ext)")

        var body: [String: Any] = ["image_url": imageURL, "audio_url": audioURL,
                                   "prompt": AvatarVideo.directions]
        body.merge(model.falInput) { _, extra in extra }
        var request = URLRequest(url: Self.queueBase.appending(path: endpoint),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.lifetime(Self.videoLifetime), forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await PipelineHTTP.send(request, failure: "fal.ai couldn't start the video",
                                               explanations: [401: Self.badKeyMessage])

        struct Response: Decodable {
            let requestID: String?

            enum CodingKeys: String, CodingKey {
                case requestID = "request_id"
            }
        }
        guard let id = try JSONDecoder().decode(Response.self, from: data).requestID, !id.isEmpty else {
            throw PipelineError(message: "fal.ai didn't say which video it started.")
        }
        return id
    }

    /// Where a video fal.ai is making has got to.
    func checkVideo(_ id: String, endpoint: String) async throws -> VideoGeneration {
        let requestURL = Self.requestURL(id, endpoint: endpoint)
        var statusRequest = URLRequest(url: requestURL.appending(path: "status"), timeoutInterval: 60)
        authorize(&statusRequest)
        let statusData = try await PipelineHTTP.send(statusRequest, failure: "Couldn't check on the video",
                                                     explanations: [401: Self.badKeyMessage])

        struct Status: Decodable {
            let status: String?
            let error: String?
        }
        let status = try JSONDecoder().decode(Status.self, from: statusData)
        guard status.status == "COMPLETED" else { return .working }
        if let error = status.error, !error.isEmpty {
            throw VideoFailed(message: "fal.ai couldn't make the video: \(error) Failed videos aren't charged.")
        }

        var resultRequest = URLRequest(url: requestURL, timeoutInterval: 60)
        authorize(&resultRequest)
        let resultData = try await PipelineHTTP.send(resultRequest, failure: "Couldn't fetch the finished video")
        struct Result: Decodable {
            struct File: Decodable { let url: String }
            let video: File?
        }
        guard let link = try JSONDecoder().decode(Result.self, from: resultData).video?.url,
              let url = URL(string: link)
        else {
            throw VideoFailed(message: "fal.ai finished but didn't send back a video.")
        }
        return .finished(url)
    }

    /// Checks on a video until it's finished, then downloads it.
    func waitForVideo(_ id: String, endpoint: String) async throws -> Data {
        while true {
            if case .finished(let url) = try await checkVideo(id, endpoint: endpoint) {
                return try await PipelineHTTP.send(URLRequest(url: url, timeoutInterval: PipelineConfig.requestTimeout),
                                                   failure: "Couldn't download the video")
            }
            try await Task.sleep(for: AvatarVideo.pollInterval)
        }
    }

    // MARK: Plumbing

    /// Puts a file in fal's storage and returns the address models read it from.
    private func upload(_ data: Data, contentType: String, fileName: String) async throws -> String {
        var components = URLComponents(url: Self.restBase.appending(path: "storage/upload/initiate"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "storage_type", value: "fal-cdn-v3")]
        var initiate = URLRequest(url: components.url!, timeoutInterval: 60)
        initiate.httpMethod = "POST"
        authorize(&initiate)
        initiate.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiate.setValue(Self.lifetime(Self.uploadLifetime), forHTTPHeaderField: "X-Fal-Object-Lifecycle")
        initiate.httpBody = try JSONSerialization.data(withJSONObject: ["content_type": contentType,
                                                                        "file_name": fileName])
        let reply = try await PipelineHTTP.send(initiate, failure: "Couldn't upload to fal.ai",
                                                explanations: [401: Self.badKeyMessage])

        struct Slot: Decodable {
            let uploadURL: String
            let fileURL: String

            enum CodingKeys: String, CodingKey {
                case uploadURL = "upload_url"
                case fileURL = "file_url"
            }
        }
        let slot = try JSONDecoder().decode(Slot.self, from: reply)
        guard let uploadURL = URL(string: slot.uploadURL) else {
            throw PipelineError(message: "fal.ai gave an upload address Pearl Forge couldn't read.")
        }
        var put = URLRequest(url: uploadURL, timeoutInterval: PipelineConfig.requestTimeout)
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        put.httpBody = data
        _ = try await PipelineHTTP.send(put, failure: "Couldn't upload to fal.ai")
        return slot.fileURL
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// A queued request's address. fal files requests under the owner and app
    /// only ("fal-ai/kling-video"), not the model's full path.
    private static func requestURL(_ id: String, endpoint: String) -> URL {
        let app = endpoint.split(separator: "/").prefix(2).joined(separator: "/")
        return queueBase.appending(path: app).appending(path: "requests").appending(path: id)
    }

    private static func lifetime(_ seconds: Int) -> String {
        "{\"expiration_duration_seconds\":\(seconds)}"
    }

    private static func audioContentType(_ fileExtension: String) -> String {
        switch fileExtension {
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        default: return "audio/mpeg"
        }
    }
}
