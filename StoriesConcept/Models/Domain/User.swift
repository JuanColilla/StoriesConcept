import Foundation

struct User: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let avatarURL: URL
    var stories: [Story]
}
