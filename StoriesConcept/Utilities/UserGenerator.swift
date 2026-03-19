import Foundation

enum UserGenerator {
    /// Generate a block of users from content pools.
    /// Returns both domain users and persisted users for SwiftData storage.
    static func generate(
        blockIndex: Int,
        photos: [PexelsPhoto],
        videos: [PexelsVideo],
        avatars: [PexelsPhoto]
    ) -> (users: [User], persisted: [PersistedUser]) {
        var usedNames: Set<String> = []
        var newUsers: [User] = []
        var persistedUsers: [PersistedUser] = []

        let shuffledPhotos = photos.shuffled()
        let shuffledVideos = videos.shuffled()
        var photoIdx = 0
        var videoIdx = 0

        for _ in 0..<Constants.usersPerBlock {
            var name: String
            repeat {
                let baseName = Constants.namePool.randomElement()!
                let suffix = Int.random(in: 10...9999)
                name = "\(baseName)_\(suffix)"
            } while usedNames.contains(name)
            usedNames.insert(name)

            let userId = name
            let avatar = avatars.randomElement()
            let avatarURLString = avatar?.src.medium ?? "https://via.placeholder.com/100"
            let avatarURL = URL(string: avatarURLString)!

            let storyCount = Int.random(in: Constants.minStoriesPerUser...Constants.maxStoriesPerUser)
            var stories: [Story] = []
            var persistedStories: [PersistedStory] = []

            for _ in 0..<storyCount {
                let useVideo = Bool.random() && !shuffledVideos.isEmpty

                if useVideo {
                    let video = shuffledVideos[videoIdx % shuffledVideos.count]
                    videoIdx += 1

                    if let videoFile = PexelsService.selectVideoFile(from: video.videoFiles),
                       let mediaURL = URL(string: videoFile.link) {
                        let mediaId = String(video.id)
                        let compositeId = Story.compositeId(userId: userId, mediaId: mediaId, blockIndex: blockIndex)
                        let duration = min(TimeInterval(video.duration), Constants.maxVideoDuration)
                        let postedAt = Date().addingTimeInterval(-Double.random(in: 3600...86400))

                        stories.append(Story(
                            id: compositeId, mediaId: mediaId, mediaURL: mediaURL,
                            type: .video, duration: duration, postedAt: postedAt
                        ))
                        persistedStories.append(PersistedStory(
                            mediaId: mediaId, mediaURL: videoFile.link,
                            mediaType: "video", duration: duration, postedAt: postedAt
                        ))
                    }
                } else if !shuffledPhotos.isEmpty {
                    let photo = shuffledPhotos[photoIdx % shuffledPhotos.count]
                    photoIdx += 1

                    if let mediaURL = URL(string: photo.src.portrait) {
                        let mediaId = String(photo.id)
                        let compositeId = Story.compositeId(userId: userId, mediaId: mediaId, blockIndex: blockIndex)
                        let postedAt = Date().addingTimeInterval(-Double.random(in: 3600...86400))

                        stories.append(Story(
                            id: compositeId, mediaId: mediaId, mediaURL: mediaURL,
                            type: .photo, duration: Constants.photoAutoAdvanceDuration, postedAt: postedAt
                        ))
                        persistedStories.append(PersistedStory(
                            mediaId: mediaId, mediaURL: photo.src.portrait,
                            mediaType: "photo", duration: Constants.photoAutoAdvanceDuration, postedAt: postedAt
                        ))
                    }
                }
            }

            guard !stories.isEmpty else { continue }

            newUsers.append(User(id: userId, displayName: userId, avatarURL: avatarURL, stories: stories))
            persistedUsers.append(PersistedUser(
                id: userId, displayName: userId, blockIndex: blockIndex,
                avatarURL: avatarURLString, stories: persistedStories
            ))
        }

        return (newUsers, persistedUsers)
    }

    /// Convert a persisted user back to a domain user.
    static func toDomainUser(_ persisted: PersistedUser) -> User {
        let stories = persisted.stories.compactMap { ps -> Story? in
            guard let url = URL(string: ps.mediaURL) else { return nil }
            let type: MediaType = ps.mediaType == "video" ? .video : .photo
            let compositeId = Story.compositeId(
                userId: persisted.id, mediaId: ps.mediaId, blockIndex: persisted.blockIndex
            )
            return Story(
                id: compositeId, mediaId: ps.mediaId, mediaURL: url,
                type: type, duration: ps.duration, postedAt: ps.postedAt
            )
        }
        return User(
            id: persisted.id, displayName: persisted.displayName,
            avatarURL: URL(string: persisted.avatarURL) ?? URL(string: "https://via.placeholder.com/100")!,
            stories: stories
        )
    }
}
