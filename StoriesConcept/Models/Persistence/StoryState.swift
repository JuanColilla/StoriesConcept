import Foundation
import SwiftData

@Model
final class StoryState {
    @Attribute(.unique) var storyId: String
    var isLiked: Bool
    var isSeen: Bool
    var seenAt: Date?

    init(storyId: String, isLiked: Bool = false, isSeen: Bool = false, seenAt: Date? = nil) {
        self.storyId = storyId
        self.isLiked = isLiked
        self.isSeen = isSeen
        self.seenAt = seenAt
    }
}
