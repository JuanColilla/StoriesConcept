import Foundation
import SwiftData

@Observable
@MainActor
final class PersistenceService {
    private let container: ModelContainer
    private var context: ModelContext

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
    }

    func isLiked(storyId: String) -> Bool {
        fetchState(storyId: storyId)?.isLiked ?? false
    }

    func markSeen(storyId: String) {
        let state = fetchOrCreateState(storyId: storyId)
        state.isSeen = true
        state.seenAt = Date()
        try? context.save()
    }

    func isSeen(storyId: String) -> Bool {
        fetchState(storyId: storyId)?.isSeen ?? false
    }

    func unseenCount(storyIds: [String]) -> Int {
        storyIds.filter { !isSeen(storyId: $0) }.count
    }

    func allSeen(storyIds: [String]) -> Bool {
        unseenCount(storyIds: storyIds) == 0
    }

    func firstUnseenIndex(storyIds: [String]) -> Int {
        for (index, id) in storyIds.enumerated() {
            if !isSeen(storyId: id) { return index }
        }
        return 0 // All seen -> start from beginning
    }

    // MARK: - Private

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
