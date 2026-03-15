import Foundation

struct PexelsVideoResponse: Codable, Sendable {
    let videos: [PexelsVideo]
    let page: Int
    let perPage: Int
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case videos, page
        case perPage = "per_page"
        case nextPage = "next_page"
    }
}

struct PexelsVideo: Codable, Identifiable, Sendable {
    let id: Int
    let width: Int
    let height: Int
    let duration: Int
    let image: String
    let videoFiles: [PexelsVideoFile]

    enum CodingKeys: String, CodingKey {
        case id, width, height, duration, image
        case videoFiles = "video_files"
    }
}

struct PexelsVideoFile: Codable, Identifiable, Sendable {
    let id: Int
    let quality: String
    let fileType: String
    let width: Int?
    let height: Int?
    let fps: Double?
    let link: String

    enum CodingKeys: String, CodingKey {
        case id, quality, width, height, fps, link
        case fileType = "file_type"
    }
}
