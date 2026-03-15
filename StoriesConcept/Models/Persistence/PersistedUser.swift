import Foundation
import SwiftData

struct PersistedStory: Codable, Sendable {
    let pexelsMediaId: String
    let mediaURL: String
    let mediaType: String
    let duration: TimeInterval
    let postedAt: Date
}

@Model
final class PersistedUser {
    @Attribute(.unique) var id: String
    var displayName: String
    var blockIndex: Int
    var avatarURL: String
    var storiesData: Data // Encoded [PersistedStory]

    init(id: String, displayName: String, blockIndex: Int, avatarURL: String, stories: [PersistedStory]) {
        self.id = id
        self.displayName = displayName
        self.blockIndex = blockIndex
        self.avatarURL = avatarURL
        self.storiesData = (try? JSONEncoder().encode(stories)) ?? Data()
    }

    var stories: [PersistedStory] {
        (try? JSONDecoder().decode([PersistedStory].self, from: storiesData)) ?? []
    }
}
