import Foundation
import SwiftData

@Observable
@MainActor
final class PersistenceService {
    private let container: ModelContainer
    private var context: ModelContext

    /// In-memory cache of seen story IDs to avoid repeated SwiftData queries.
    /// Populated lazily on first access and updated on markSeen().
    /// Eliminates O(N) DB queries per row when scrolling the story list.
    private var seenCache: Set<String>?
    /// In-memory cache of liked story IDs, same pattern as seenCache.
    private var likedCache: Set<String>?

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    // MARK: - Users

    func saveUser(_ user: PersistedUser) {
        context.insert(user)
        try? context.save()
    }

    func saveUsers(_ users: [PersistedUser]) {
        users.forEach { context.insert($0) }
        try? context.save()
    }

    func fetchUsers(blockIndex: Int? = nil) -> [PersistedUser] {
        var descriptor = FetchDescriptor<PersistedUser>()
        if let blockIndex {
            descriptor.predicate = #Predicate { $0.blockIndex == blockIndex }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchAllUsers() -> [PersistedUser] {
        let descriptor = FetchDescriptor<PersistedUser>(
            sortBy: [SortDescriptor(\.blockIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func maxBlockIndex() -> Int {
        let users = fetchAllUsers()
        return users.map(\.blockIndex).max() ?? -1
    }

    // MARK: - Story States

    func setLiked(storyId: String, liked: Bool) {
        let state = fetchOrCreateState(storyId: storyId)
        state.isLiked = liked
        try? context.save()

        // Keep cache in sync
        if liked {
            likedCache?.insert(storyId)
        } else {
            likedCache?.remove(storyId)
        }
    }

    func isLiked(storyId: String) -> Bool {
        loadLikedCacheIfNeeded()
        return likedCache?.contains(storyId) ?? false
    }

    func markSeen(storyId: String) {
        let state = fetchOrCreateState(storyId: storyId)
        state.isSeen = true
        state.seenAt = Date()
        try? context.save()

        // Keep cache in sync — avoids re-querying on next scroll
        seenCache?.insert(storyId)
    }

    func isSeen(storyId: String) -> Bool {
        loadSeenCacheIfNeeded()
        return seenCache?.contains(storyId) ?? false
    }

    func unseenCount(storyIds: [String]) -> Int {
        loadSeenCacheIfNeeded()
        return storyIds.filter { !(seenCache?.contains($0) ?? false) }.count
    }

    func allSeen(storyIds: [String]) -> Bool {
        unseenCount(storyIds: storyIds) == 0
    }

    func firstUnseenIndex(storyIds: [String]) -> Int {
        loadSeenCacheIfNeeded()
        for (index, id) in storyIds.enumerated() {
            if !(seenCache?.contains(id) ?? false) { return index }
        }
        return 0 // All seen -> start from beginning
    }

    // MARK: - Private

    /// Loads all seen story IDs from SwiftData into memory on first access.
    /// Subsequent calls are no-ops — the cache is kept in sync by markSeen().
    private func loadSeenCacheIfNeeded() {
        guard seenCache == nil else { return }
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.isSeen == true }
        )
        let states = (try? context.fetch(descriptor)) ?? []
        seenCache = Set(states.map(\.storyId))
    }

    /// Loads all liked story IDs from SwiftData into memory on first access.
    private func loadLikedCacheIfNeeded() {
        guard likedCache == nil else { return }
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.isLiked == true }
        )
        let states = (try? context.fetch(descriptor)) ?? []
        likedCache = Set(states.map(\.storyId))
    }

    private func fetchState(storyId: String) -> StoryState? {
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.storyId == storyId }
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateState(storyId: String) -> StoryState {
        if let existing = fetchState(storyId: storyId) { return existing }
        let state = StoryState(storyId: storyId)
        context.insert(state)
        return state
    }
}
