import AVFoundation
import Foundation
import UIKit

/// Video pearls: a picture of your ElevenLabs avatar, lip-synced to a pearl's
/// audio by one of the models in VideoModel. ElevenLabs' own Avatars page
/// has no API yet, so the app works from a picture of the avatar instead.
enum AvatarVideo {
    static let model = "creatify-aurora"
    static let resolution = "720p"
    /// ElevenLabs asks apps to check on a video no more than every 10 seconds.
    static let pollInterval: Duration = .seconds(10)
    static let chosenModelKey = "videoModel"

    static let needsProMessage = "Making videos from the app needs ElevenLabs Pro or higher. On your plan, make the video in ElevenLabs Avatars instead, then use Add video."

    /// Whether your plan lets apps make videos: false below Pro, nil when the
    /// plan isn't known (the attempt then tells you).
    static func planAllowsApp(tier: String?) -> Bool? {
        guard let tier = tier?.lowercased(), !tier.isEmpty else { return nil }
        return !["free", "starter", "creator"].contains(where: tier.hasPrefix)
    }

    // MARK: The avatar picture

    private static var pictureURL: URL {
        URL.applicationSupportDirectory.appending(path: "AvatarPicture.jpg")
    }

    static var picture: Data? {
        try? Data(contentsOf: pictureURL)
    }

    /// Saves a picture of your avatar as a JPEG no bigger than 1280 pixels on
    /// its longer side, plenty for a 720p video.
    static func savePicture(_ data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw PipelineError(message: "That picture couldn't be opened. Try saving it again as a photo.")
        }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.9) else {
            throw PipelineError(message: "That picture couldn't be saved.")
        }
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: pictureURL, options: .atomic)
    }

    static func removePicture() {
        try? FileManager.default.removeItem(at: pictureURL)
    }

    // MARK: Cost

    /// How long the pearl's audio plays for.
    static func seconds(of audio: Data) -> Double? {
        (try? AVAudioPlayer(data: audio)).map(\.duration).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Credits per second of speech, from the videos Pearl Forge made before
    /// (the middle of the last five), or nil before the first one.
    static func creditsPerSecond(from pearls: [Pearl]) -> Double? {
        let rates = pearls
            .filter { $0.videoGenerationID == nil }
            .sorted { $0.created > $1.created }
            .compactMap { pearl -> Double? in
                guard let credits = pearl.videoCredits, let seconds = pearl.videoSeconds, seconds > 0 else { return nil }
                return Double(credits) / seconds
            }
            .prefix(5)
            .sorted()
        return rates.isEmpty ? nil : rates[rates.count / 2]
    }
}

/// What animates the avatar picture: ElevenLabs (Pro plans and up), or one
/// of the avatar models on fal.ai, paid per second of video with no
/// subscription.
struct VideoModel: Identifiable, Hashable {
    /// Saved as the choice in Settings.
    let id: String
    let name: String
    /// What it's good for, under its name in the picker.
    let strength: String
    /// fal.ai's model, or nil for ElevenLabs.
    let falEndpoint: String?
    /// Extra settings sent with the picture and audio.
    var falInput: [String: String] = [:]
    /// fal.ai's list price per second of video, as of November 2026.
    var dollarsPerSecond: Double?
    /// Creatify bills whole seconds: a 9.4-second video costs as much as 10.
    var billsWholeSeconds = false
    /// The longest pearl the model can take, in seconds.
    var maxSeconds: Double?

    var isFal: Bool { falEndpoint != nil }

    /// What a video of this many seconds of speech should cost, in dollars.
    func cost(seconds: Double) -> Double? {
        dollarsPerSecond.map { (billsWholeSeconds ? seconds.rounded(.up) : seconds) * $0 }
    }

    /// "$3.37 a minute", or what ElevenLabs needs.
    var priceLine: String {
        guard let perMinute = cost(seconds: 60) else { return "Needs ElevenLabs Pro or higher" }
        return "About \(perMinute.dollars) a minute"
    }

    static let elevenLabs = VideoModel(id: "elevenlabs", name: "ElevenLabs (Creatify Aurora)",
                                       strength: "Uses your ElevenLabs plan's credits", falEndpoint: nil)

    static let fal: [VideoModel] = [
        VideoModel(id: "kling-standard", name: "Kling Avatar v2 Standard",
                   strength: "Everyday pearls, the cheapest",
                   falEndpoint: "fal-ai/kling-video/ai-avatar/v2/standard", dollarsPerSecond: 0.0562),
        VideoModel(id: "kling-pro", name: "Kling Avatar v2 Pro",
                   strength: "Sharper Kling",
                   falEndpoint: "fal-ai/kling-video/ai-avatar/v2/pro", dollarsPerSecond: 0.115),
        VideoModel(id: "aurora-480p", name: "Creatify Aurora, 480p",
                   strength: "The model ElevenLabs uses, smaller picture",
                   falEndpoint: "fal-ai/creatify/aurora", falInput: ["resolution": "480p"],
                   dollarsPerSecond: 0.07, billsWholeSeconds: true),
        VideoModel(id: "aurora-720p", name: "Creatify Aurora, 720p",
                   strength: "The model ElevenLabs uses",
                   falEndpoint: "fal-ai/creatify/aurora", falInput: ["resolution": "720p"],
                   dollarsPerSecond: 0.14, billsWholeSeconds: true),
        VideoModel(id: "omnihuman", name: "OmniHuman 1.5",
                   strength: "Most lifelike gestures; pearls up to 1 minute",
                   falEndpoint: "fal-ai/bytedance/omnihuman/v1.5", falInput: ["resolution": "720p"],
                   dollarsPerSecond: 0.16, maxSeconds: 60),
    ]

    static let all = fal + [elevenLabs]
    static let standard = fal[0]

    static func withID(_ id: String?) -> VideoModel {
        all.first { $0.id == id } ?? standard
    }

    /// The name of the fal.ai model a video was made with.
    static func name(ofEndpoint endpoint: String) -> String {
        let name = fal.first { $0.falEndpoint == endpoint }?.name ?? endpoint
        // Both Aurora sizes share one model.
        return name.components(separatedBy: ",").first ?? name
    }
}

/// ElevenLabs or fal.ai gave up on a video. Unlike a lost connection, there's
/// nothing left to collect.
struct VideoFailed: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// A video ElevenLabs or fal.ai is making: still going, or finished with a
/// download link.
enum VideoGeneration {
    case working
    case finished(URL)
}

extension ElevenLabsClient {
    /// Starts a lip-synced video of the picture speaking the audio, and
    /// returns its id for checkVideo.
    func startLipSyncVideo(picture: Data, audio: Data) async throws -> String {
        let body: [String: Any] = [
            "model_id": AvatarVideo.model,
            "resolution": AvatarVideo.resolution,
            "image": ["type": "inline_base64", "content_base64": picture.base64EncodedString(),
                      "mime_type": "image/jpeg"],
            "audio": ["type": "inline_base64", "content_base64": audio.base64EncodedString(),
                      "mime_type": "audio/mpeg"],
        ]
        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appending(path: "flows/video"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await PipelineHTTP.send(request, failure: "ElevenLabs couldn't start the video",
                                               explanations: [402: AvatarVideo.needsProMessage])

        struct Response: Decodable { let id: String? }
        guard let id = try JSONDecoder().decode(Response.self, from: data).id, !id.isEmpty else {
            throw PipelineError(message: "ElevenLabs didn't say which video it started.")
        }
        return id
    }

    /// Where a video ElevenLabs is making has got to. Its download link
    /// expires after about an hour, so ask again rather than keeping it.
    func checkVideo(_ id: String) async throws -> VideoGeneration {
        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appending(path: "flows/video")
                                    .appending(path: id),
                                 timeoutInterval: 60)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let data = try await PipelineHTTP.send(request, failure: "Couldn't check on the video")

        struct Response: Decodable {
            let status: String?
            let contentURL: String?
            let errorMessage: String?

            enum CodingKeys: String, CodingKey {
                case status
                case contentURL = "content_url"
                case errorMessage = "error_message"
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        switch response.status {
        case "completed":
            guard let link = response.contentURL, let url = URL(string: link) else {
                throw PipelineError(message: "ElevenLabs finished the video but didn't say where it is.")
            }
            return .finished(url)
        case "failed":
            throw VideoFailed(message: "ElevenLabs couldn't make the video: "
                                + (response.errorMessage ?? "it didn't say why.") + " Failed videos aren't charged.")
        default:
            return .working
        }
    }

    /// Checks on a video until it's finished, then downloads it.
    func waitForVideo(_ id: String) async throws -> Data {
        while true {
            if case .finished(let url) = try await checkVideo(id) {
                return try await PipelineHTTP.send(URLRequest(url: url, timeoutInterval: PipelineConfig.requestTimeout),
                                                   failure: "Couldn't download the video")
            }
            try await Task.sleep(for: AvatarVideo.pollInterval)
        }
    }
}
