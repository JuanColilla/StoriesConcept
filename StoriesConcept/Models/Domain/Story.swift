import Foundation

struct Story: Identifiable, Sendable {
    /// Composite ID: "\(userId)_\(mediaId)_\(blockIndex)"
    let id: String
    /// Pexels media ID — used as cache key, shared across users for same content
    let mediaId: String
    let mediaURL: URL
    let type: MediaType
    /// 15s for photos, actual duration (capped 45s) for videos
    let duration: TimeInterval
    let postedAt: Date

    /// Cache key — shared across users for same Pexels content
    var cacheKey: String { mediaId }

    static func compositeId(userId: String, mediaId: String, blockIndex: Int) -> String {
        "\(userId)_\(mediaId)_\(blockIndex)"
    }
}
