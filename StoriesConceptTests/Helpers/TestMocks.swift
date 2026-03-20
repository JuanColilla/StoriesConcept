import Foundation
@testable import StoriesConcept

// MARK: - Story Mocks

extension Story {
    static let photoMock = Story(
        id: "user1_photo1_0",
        mediaId: "photo1",
        mediaURL: URL(string: "https://example.com/photo1.jpg")!,
        type: .photo,
        duration: Constants.photoAutoAdvanceDuration,
        postedAt: Date(timeIntervalSince1970: 1_000_000)
    )

    static let photoMock2 = Story(
        id: "user1_photo2_0",
        mediaId: "photo2",
        mediaURL: URL(string: "https://example.com/photo2.jpg")!,
        type: .photo,
        duration: Constants.photoAutoAdvanceDuration,
        postedAt: Date(timeIntervalSince1970: 1_000_100)
    )

    static let videoMock = Story(
        id: "user1_video1_0",
        mediaId: "video1",
        mediaURL: URL(string: "https://example.com/video1.mp4")!,
        type: .video,
        duration: 10,
        postedAt: Date(timeIntervalSince1970: 1_000_200)
    )
}

// MARK: - User Mocks

extension User {
    static let singleStoryUser = User(
        id: "user1",
        displayName: "emma_42",
        avatarURL: URL(string: "https://example.com/avatar1.jpg")!,
        stories: [.photoMock]
    )

    static let multiStoryUser = User(
        id: "user1",
        displayName: "emma_42",
        avatarURL: URL(string: "https://example.com/avatar1.jpg")!,
        stories: [.photoMock, .photoMock2, .videoMock]
    )

    static let secondUser = User(
        id: "user2",
        displayName: "jake_99",
        avatarURL: URL(string: "https://example.com/avatar2.jpg")!,
        stories: [
            Story(
                id: "user2_photo3_0",
                mediaId: "photo3",
                mediaURL: URL(string: "https://example.com/photo3.jpg")!,
                type: .photo,
                duration: Constants.photoAutoAdvanceDuration,
                postedAt: Date(timeIntervalSince1970: 1_000_300)
            )
        ]
    )
}
