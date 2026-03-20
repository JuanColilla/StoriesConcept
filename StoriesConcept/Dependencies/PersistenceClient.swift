import ComposableArchitecture
import Foundation
import os
import SwiftData

// MARK: - Client Interface

struct PersistenceClient: Sendable {
    // Users
    var saveUsers: @Sendable (_ users: [PersistedUser]) async throws -> Void
    var fetchAllUsers: @Sendable () async throws -> [PersistedUser]
    var fetchUsers: @Sendable (_ blockIndex: Int) async throws -> [PersistedUser]
    var maxBlockIndex: @Sendable () async -> Int
    // Story states
    var markSeen: @Sendable (_ storyId: String) async throws -> Void
    var setLiked: @Sendable (_ storyId: String, _ liked: Bool) async throws -> Void
    var isSeen: @Sendable (_ storyId: String) async -> Bool
    var isLiked: @Sendable (_ storyId: String) async -> Bool
    var unseenCount: @Sendable (_ storyIds: [String]) async -> Int
    var allSeen: @Sendable (_ storyIds: [String]) async -> Bool
    var firstUnseenIndex: @Sendable (_ storyIds: [String]) async -> Int
    // Cache bootstrap
    var loadSeenCache: @Sendable () async throws -> Set<String>
    var loadLikedCache: @Sendable () async throws -> Set<String>
}

// MARK: - MainActor Storage (wraps ModelContext safely)

@MainActor
private final class PersistenceStorage {
    private let context: ModelContext
    private var seenCache: Set<String>?
    private var likedCache: Set<String>?

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    func saveUsers(_ users: [PersistedUser]) throws {
        users.forEach { context.insert($0) }
        try context.save()
        Logger.persist.info("Saved \(users.count, privacy: .public) users")
    }

    func fetchAllUsers() -> [PersistedUser] {
        let descriptor = FetchDescriptor<PersistedUser>(
            sortBy: [SortDescriptor(\.blockIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchUsers(blockIndex: Int) -> [PersistedUser] {
        var descriptor = FetchDescriptor<PersistedUser>()
        descriptor.predicate = #Predicate { $0.blockIndex == blockIndex }
        return (try? context.fetch(descriptor)) ?? []
    }

    func maxBlockIndex() -> Int {
        fetchAllUsers().map(\.blockIndex).max() ?? -1
    }

    func markSeen(storyId: String) throws {
        let state = fetchOrCreateState(storyId: storyId)
        state.isSeen = true
        state.seenAt = Date()
        try context.save()
        seenCache?.insert(storyId)
        Logger.persist.info("Marked seen: \(storyId, privacy: .public)")
    }

    func setLiked(storyId: String, liked: Bool) throws {
        let state = fetchOrCreateState(storyId: storyId)
        state.isLiked = liked
        try context.save()
        if liked { likedCache?.insert(storyId) } else { likedCache?.remove(storyId) }
    }

    func isSeen(storyId: String) -> Bool {
        loadSeenCacheIfNeeded()
        return seenCache?.contains(storyId) ?? false
    }

    func isLiked(storyId: String) -> Bool {
        loadLikedCacheIfNeeded()
        return likedCache?.contains(storyId) ?? false
    }

    func unseenCount(storyIds: [String]) -> Int {
        loadSeenCacheIfNeeded()
        return storyIds.filter { !(seenCache?.contains($0) ?? false) }.count
    }

    func allSeen(storyIds: [String]) -> Bool {
        loadSeenCacheIfNeeded()
        return storyIds.allSatisfy { seenCache?.contains($0) ?? false }
    }

    func firstUnseenIndex(storyIds: [String]) -> Int {
        loadSeenCacheIfNeeded()
        for (index, id) in storyIds.enumerated() {
            if !(seenCache?.contains(id) ?? false) { return index }
        }
        return 0
    }

    func loadSeenCache() -> Set<String> {
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.isSeen == true }
        )
        let states = (try? context.fetch(descriptor)) ?? []
        let ids = Set(states.map(\.storyId))
        seenCache = ids
        return ids
    }

    func loadLikedCache() -> Set<String> {
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.isLiked == true }
        )
        let states = (try? context.fetch(descriptor)) ?? []
        let ids = Set(states.map(\.storyId))
        likedCache = ids
        return ids
    }

    // MARK: - Private

    private func loadSeenCacheIfNeeded() {
        guard seenCache == nil else { return }
        _ = loadSeenCache()
    }

    private func loadLikedCacheIfNeeded() {
        guard likedCache == nil else { return }
        _ = loadLikedCache()
    }

    private func fetchOrCreateState(storyId: String) -> StoryState {
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
}

// MARK: - Dependency Key

extension PersistenceClient: DependencyKey {
    @MainActor
    static func live(container: ModelContainer) -> PersistenceClient {
        let storage = PersistenceStorage(container: container)

        return PersistenceClient(
            saveUsers: { users in await storage.saveUsers(users) },
            fetchAllUsers: { await storage.fetchAllUsers() },
            fetchUsers: { blockIndex in await storage.fetchUsers(blockIndex: blockIndex) },
            maxBlockIndex: { await storage.maxBlockIndex() },
            markSeen: { storyId in try await storage.markSeen(storyId: storyId) },
            setLiked: { storyId, liked in try await storage.setLiked(storyId: storyId, liked: liked) },
            isSeen: { storyId in await storage.isSeen(storyId: storyId) },
            isLiked: { storyId in await storage.isLiked(storyId: storyId) },
            unseenCount: { storyIds in await storage.unseenCount(storyIds: storyIds) },
            allSeen: { storyIds in await storage.allSeen(storyIds: storyIds) },
            firstUnseenIndex: { storyIds in await storage.firstUnseenIndex(storyIds: storyIds) },
            loadSeenCache: { await storage.loadSeenCache() },
            loadLikedCache: { await storage.loadLikedCache() }
        )
    }

    static let liveValue: PersistenceClient = {
        fatalError("PersistenceClient.liveValue must be configured with a ModelContainer")
    }()

    static let testValue = PersistenceClient(
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
