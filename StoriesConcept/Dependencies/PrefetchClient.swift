import ComposableArchitecture
import Foundation
import os

@DependencyClient
struct PrefetchClient: Sendable {
    var prefetchThumbnails: @Sendable (_ users: [User]) async -> Void
    var prefetchStories: @Sendable (_ currentUser: User, _ nextUser: User?) async -> Void
    var cancelAll: @Sendable () -> Void = { }
}

extension PrefetchClient: DependencyKey {
    static let liveValue: PrefetchClient = {
        let manager = PrefetchActor()
        return PrefetchClient(
            prefetchThumbnails: { users in
                await manager.prefetchThumbnails(for: users)
            },
            prefetchStories: { currentUser, nextUser in
                await manager.prefetchStories(currentUser: currentUser, nextUser: nextUser)
            },
            cancelAll: {
                Task { await manager.cancelAll() }
            }
        )
    }()

    static let previewValue = PrefetchClient(
        prefetchThumbnails: { _ in },
        prefetchStories: { _, _ in },
        cancelAll: { }
    )
}

extension DependencyValues {
    var prefetchClient: PrefetchClient {
        get { self[PrefetchClient.self] }
        set { self[PrefetchClient.self] = newValue }
    }
}

// MARK: - Actor-based prefetch manager (Swift 6 safe)

private actor PrefetchActor {
    private var activeTasks: [String: Task<Void, Never>] = [:]

    @Dependency(\.cacheClient) var cacheClient
    @Dependency(\.pexelsClient) var pexelsClient

    func prefetchThumbnails(for users: [User]) {
        for user in users {
            guard let firstStory = user.stories.first else { continue }
            let cacheKey = firstStory.cacheKey
            guard !cacheClient.isAvailable(cacheKey) else { continue }

            let taskKey = "thumb_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = firstStory.mediaURL
            activeTasks[taskKey] = Task.detached(priority: .background) { [cacheClient, pexelsClient] in
                do {
                    let data = try await pexelsClient.downloadData(url)
                    await cacheClient.save(data, cacheKey, Constants.cacheTTL)
                } catch {
                    // Silent failure
                }
            }
        }
    }

    func prefetchStories(currentUser: User, nextUser: User?) {
        prefetchAllStories(for: currentUser, priority: .userInitiated)
        if let nextUser {
            prefetchAllStories(for: nextUser, priority: .background)
        }
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        Logger.prefetch.info("All prefetch tasks cancelled")
    }

    private func prefetchAllStories(for user: User, priority: TaskPriority) {
        for story in user.stories where story.type == .photo {
            let cacheKey = story.cacheKey
            guard !cacheClient.isAvailable(cacheKey) else { continue }

            let taskKey = "story_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = story.mediaURL
            activeTasks[taskKey] = Task.detached(priority: priority) { [cacheClient, pexelsClient] in
                do {
                    let data = try await pexelsClient.downloadData(url)
                    await cacheClient.save(data, cacheKey, Constants.cacheTTL)
                } catch {
                    // Silent failure
                }
            }
        }
    }
}
