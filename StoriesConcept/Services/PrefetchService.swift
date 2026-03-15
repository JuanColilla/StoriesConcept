import Foundation

@Observable
@MainActor
final class PrefetchService {
    private let pexelsService: PexelsService
    private let cacheService: CacheService
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(pexelsService: PexelsService, cacheService: CacheService) {
        self.pexelsService = pexelsService
        self.cacheService = cacheService
    }

    /// Thumbnail prefetch for list screen — download first story image for each visible user
    func prefetchThumbnails(for users: [User]) {
        for user in users {
            guard let firstStory = user.stories.first else { continue }
            let cacheKey = firstStory.cacheKey
            guard !cacheService.isAvailable(mediaId: cacheKey) else { continue }

            let taskKey = "thumb_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = firstStory.mediaURL
            let pexels = pexelsService
            let cache = cacheService

            activeTasks[taskKey] = Task.detached(priority: .background) {
                do {
                    let data = try await pexels.downloadData(from: url)
                    await MainActor.run { cache.save(data: data, for: cacheKey) }
                } catch {
                    // Silent failure — will retry on demand
                }
            }
        }
    }

    /// Linear prefetch for player screen — download all content for current + next user
    func prefetchStories(currentUser: User, nextUser: User?) {
        prefetchAllStories(for: currentUser, priority: .userInitiated)
        if let nextUser {
            prefetchAllStories(for: nextUser, priority: .background)
        }
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }

    // MARK: - Private

    private func prefetchAllStories(for user: User, priority: TaskPriority) {
        for story in user.stories {
            let cacheKey = story.cacheKey
            guard !cacheService.isAvailable(mediaId: cacheKey) else { continue }

            let taskKey = "story_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = story.mediaURL
            let pexels = pexelsService
            let cache = cacheService

            activeTasks[taskKey] = Task.detached(priority: priority) {
                do {
                    let data = try await pexels.downloadData(from: url)
                    await MainActor.run { cache.save(data: data, for: cacheKey) }
                } catch {
                    // Silent failure
                }
            }
        }
    }
}
