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
        let manager = PrefetchManager()
        return PrefetchClient(
            prefetchThumbnails: { users in
                await manager.prefetchThumbnails(for: users)
            },
            prefetchStories: { currentUser, nextUser in
                await manager.prefetchStories(currentUser: currentUser, nextUser: nextUser)
            },
            cancelAll: {
                manager.cancelAll()
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

// MARK: - Prefetch Manager (internal actor)

private final class PrefetchManager: @unchecked Sendable {
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()

    @Dependency(\.cacheClient) var cacheClient
    @Dependency(\.pexelsClient) var pexelsClient

    func prefetchThumbnails(for users: [User]) async {
        for user in users {
            guard let firstStory = user.stories.first else { continue }
            let cacheKey = firstStory.cacheKey
            guard !cacheClient.isAvailable(cacheKey) else { continue }

            let taskKey = "thumb_\(cacheKey)"
            lock.lock()
            let exists = activeTasks[taskKey] != nil
            lock.unlock()
            guard !exists else { continue }

            let url = firstStory.mediaURL
            let task = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                do {
                    let data = try await self.pexelsClient.downloadData(url)
                    await self.cacheClient.save(data, cacheKey, Constants.cacheTTL)
                } catch {
                    // Silent failure — will retry on demand
                }
            }
            lock.lock()
            activeTasks[taskKey] = task
            lock.unlock()
        }
    }

    func prefetchStories(currentUser: User, nextUser: User?) async {
        await prefetchAllStories(for: currentUser, priority: .userInitiated)
        if let nextUser {
            await prefetchAllStories(for: nextUser, priority: .background)
        }
    }

    func cancelAll() {
        lock.lock()
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        lock.unlock()
        Logger.prefetch.info("All prefetch tasks cancelled")
    }

    private func prefetchAllStories(for user: User, priority: TaskPriority) async {
        for story in user.stories where story.type == .photo {
            let cacheKey = story.cacheKey
            guard !cacheClient.isAvailable(cacheKey) else { continue }

            let taskKey = "story_\(cacheKey)"
            lock.lock()
            let exists = activeTasks[taskKey] != nil
            lock.unlock()
            guard !exists else { continue }

            let url = story.mediaURL
            let task = Task.detached(priority: priority) { [weak self] in
                guard let self else { return }
                do {
                    let data = try await self.pexelsClient.downloadData(url)
                    await self.cacheClient.save(data, cacheKey, Constants.cacheTTL)
                } catch {
                    // Silent failure
                }
            }
            lock.lock()
            activeTasks[taskKey] = task
            lock.unlock()
        }
    }
}
