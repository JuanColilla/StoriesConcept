import ComposableArchitecture
import Foundation
import os
import SwiftData

// MARK: - Client Interface

@DependencyClient
struct PersistenceClient: Sendable {
    // Users
    var saveUsers: @Sendable (_ users: [PersistedUser]) async throws -> Void
    var fetchAllUsers: @Sendable () async throws -> [PersistedUser]
    var fetchUsers: @Sendable (_ blockIndex: Int) async throws -> [PersistedUser]
    var maxBlockIndex: @Sendable () async -> Int = { -1 }
    // Story states
    var markSeen: @Sendable (_ storyId: String) async throws -> Void
    var setLiked: @Sendable (_ storyId: String, _ liked: Bool) async throws -> Void
    var isSeen: @Sendable (_ storyId: String) -> Bool = { _ in false }
    var isLiked: @Sendable (_ storyId: String) -> Bool = { _ in false }
    var unseenCount: @Sendable (_ storyIds: [String]) -> Int = { $0.count }
    var allSeen: @Sendable (_ storyIds: [String]) -> Bool = { _ in false }
    var firstUnseenIndex: @Sendable (_ storyIds: [String]) -> Int = { _ in 0 }
    // Cache bootstrap
    var loadSeenCache: @Sendable () async throws -> Set<String>
    var loadLikedCache: @Sendable () async throws -> Set<String>
}

// MARK: - Live Implementation

extension PersistenceClient: DependencyKey {
    @MainActor
    static func live(container: ModelContainer) -> PersistenceClient {
        let context = container.mainContext

        // In-memory caches — kept in sync with SwiftData
        var seenCache: Set<String>?
        var likedCache: Set<String>?

        func loadSeenCacheIfNeeded() {
            guard seenCache == nil else { return }
            let descriptor = FetchDescriptor<StoryState>(
                predicate: #Predicate { $0.isSeen == true }
            )
            let states = (try? context.fetch(descriptor)) ?? []
            seenCache = Set(states.map(\.storyId))
        }

        func loadLikedCacheIfNeeded() {
            guard likedCache == nil else { return }
            let descriptor = FetchDescriptor<StoryState>(
                predicate: #Predicate { $0.isLiked == true }
            )
            let states = (try? context.fetch(descriptor)) ?? []
            likedCache = Set(states.map(\.storyId))
        }

        func fetchOrCreateState(storyId: String) -> StoryState {
            let descriptor = FetchDescriptor<StoryState>(
                predicate: #Predicate { $0.storyId == storyId }
            )
            if let existing = try? context.fetch(descriptor).first {
                return existing
            }
            let state = StoryState(storyId: storyId)
            context.insert(state)
            return state
        }

        return PersistenceClient(
            saveUsers: { users in
                users.forEach { context.insert($0) }
                try context.save()
                Logger.persist.info("Saved \(users.count, privacy: .public) users")
            },
            fetchAllUsers: {
                let descriptor = FetchDescriptor<PersistedUser>(
                    sortBy: [SortDescriptor(\.blockIndex)]
                )
                return (try? context.fetch(descriptor)) ?? []
            },
            fetchUsers: { blockIndex in
                var descriptor = FetchDescriptor<PersistedUser>()
                descriptor.predicate = #Predicate { $0.blockIndex == blockIndex }
                return (try? context.fetch(descriptor)) ?? []
            },
            maxBlockIndex: {
                let descriptor = FetchDescriptor<PersistedUser>(
                    sortBy: [SortDescriptor(\.blockIndex)]
                )
                let users = (try? context.fetch(descriptor)) ?? []
                return users.map(\.blockIndex).max() ?? -1
            },
            markSeen: { storyId in
                let state = fetchOrCreateState(storyId: storyId)
                state.isSeen = true
                state.seenAt = Date()
                try context.save()
                seenCache?.insert(storyId)
                Logger.persist.info("Marked seen: \(storyId, privacy: .public)")
            },
            setLiked: { storyId, liked in
                let state = fetchOrCreateState(storyId: storyId)
                state.isLiked = liked
                try context.save()
                if liked { likedCache?.insert(storyId) } else { likedCache?.remove(storyId) }
            },
            isSeen: { storyId in
                loadSeenCacheIfNeeded()
                return seenCache?.contains(storyId) ?? false
            },
            isLiked: { storyId in
                loadLikedCacheIfNeeded()
                return likedCache?.contains(storyId) ?? false
            },
            unseenCount: { storyIds in
                loadSeenCacheIfNeeded()
                return storyIds.filter { !(seenCache?.contains($0) ?? false) }.count
            },
            allSeen: { storyIds in
                loadSeenCacheIfNeeded()
                return storyIds.allSatisfy { seenCache?.contains($0) ?? false }
            },
            firstUnseenIndex: { storyIds in
                loadSeenCacheIfNeeded()
                for (index, id) in storyIds.enumerated() {
                    if !(seenCache?.contains(id) ?? false) { return index }
                }
                return 0
            },
            loadSeenCache: {
                let descriptor = FetchDescriptor<StoryState>(
                    predicate: #Predicate { $0.isSeen == true }
                )
                let states = (try? context.fetch(descriptor)) ?? []
                let ids = Set(states.map(\.storyId))
                seenCache = ids
                return ids
            },
            loadLikedCache: {
                let descriptor = FetchDescriptor<StoryState>(
                    predicate: #Predicate { $0.isLiked == true }
                )
                let states = (try? context.fetch(descriptor)) ?? []
                let ids = Set(states.map(\.storyId))
                likedCache = ids
                return ids
            }
        )
    }

    static let liveValue: PersistenceClient = {
        // Must be overridden in app entry point via withDependencies
        // using PersistenceClient.live(container:)
        fatalError("PersistenceClient.liveValue must be configured with a ModelContainer")
    }()

    static let previewValue = PersistenceClient(
        saveUsers: { _ in },
        fetchAllUsers: { [] },
        fetchUsers: { _ in [] },
        maxBlockIndex: { -1 },
        markSeen: { _ in },
        setLiked: { _, _ in },
        isSeen: { _ in false },
        isLiked: { _ in false },
        unseenCount: { $0.count },
        allSeen: { _ in true },
        firstUnseenIndex: { _ in 0 },
        loadSeenCache: { [] },
        loadLikedCache: { [] }
    )
}

// MARK: - Dependency Registration

extension DependencyValues {
    var persistenceClient: PersistenceClient {
        get { self[PersistenceClient.self] }
        set { self[PersistenceClient.self] = newValue }
    }
}
