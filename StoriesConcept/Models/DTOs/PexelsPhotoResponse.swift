import Foundation

struct PexelsPhotoResponse: Codable, Sendable, Equatable {
    let photos: [PexelsPhoto]
    let page: Int
    let perPage: Int
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case photos, page
        case perPage = "per_page"
        case nextPage = "next_page"
    }
}

struct PexelsPhoto: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let width: Int
    let height: Int
    let photographer: String
    let avgColor: String
    let src: PexelsSrc

    enum CodingKeys: String, CodingKey {
        case id, width, height, photographer, src
        case avgColor = "avg_color"
    }
}

struct PexelsSrc: Codable, Sendable, Equatable {
    let original: String
    let large2x: String
    let large: String
    let medium: String
    let small: String
    let portrait: String
    let landscape: String
    let tiny: String
}
