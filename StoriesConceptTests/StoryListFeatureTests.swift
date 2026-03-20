import ComposableArchitecture
import Foundation
import Testing

@testable import StoriesConcept

@Suite
@MainActor
struct StoryListFeatureTests {

    // MARK: - Initial Load

    @Test
    func initialLoadShowsLoadingThenFetchesFromPersistence() async {
        let store = TestStore(initialState: StoryListFeature.State()) {
            StoryListFeature()
        } withDependencies: {
            $0.persistenceClient.fetchAllUsers = { [] }
            $0.persistenceClient.loadSeenCache = { [] }
            $0.persistenceClient.loadLikedCache = { [] }
            $0.pexelsClient.fetchCuratedPhotos = { _, _ in [] }
            $0.pexelsClient.fetchPopularVideos = { _, _ in [] }
            $0.pexelsClient.fetchAvatarPhotos = { _, _ in [] }
            $0.persistenceClient.saveUsers = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }
    }

    @Test
    func initialLoadFailureSetsError() async {
        struct TestError: Error, LocalizedError, Equatable {
            var errorDescription: String? { "Network error" }
        }

        let store = TestStore(initialState: StoryListFeature.State()) {
            StoryListFeature()
        } withDependencies: {
            $0.persistenceClient.fetchAllUsers = { [] }
            $0.persistenceClient.loadSeenCache = { [] }
            $0.persistenceClient.loadLikedCache = { [] }
            $0.pexelsClient.fetchCuratedPhotos = { _, _ in throw TestError() }
            $0.pexelsClient.fetchPopularVideos = { _, _ in [] }
            $0.pexelsClient.fetchAvatarPhotos = { _, _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\.initialLoadResponse) {
            $0.isLoading = false
            $0.errorMessage = "Network error"
        }
    }

    @Test
    func retryAfterErrorClearsAndReloads() async {
        var state = StoryListFeature.State()
        state.errorMessage = "Some error"

        let store = TestStore(initialState: state) {
            StoryListFeature()
        } withDependencies: {
            $0.persistenceClient.fetchAllUsers = { [] }
            $0.persistenceClient.loadSeenCache = { [] }
            $0.persistenceClient.loadLikedCache = { [] }
            $0.pexelsClient.fetchCuratedPhotos = { _, _ in [] }
            $0.pexelsClient.fetchPopularVideos = { _, _ in [] }
            $0.pexelsClient.fetchAvatarPhotos = { _, _ in [] }
            $0.persistenceClient.saveUsers = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.retry) {
            $0.errorMessage = nil
            $0.users = []
        }
    }

    // MARK: - User Tap & Player Presentation

    @Test
    func userTapPresentsPlayer() async {
        var state = StoryListFeature.State()
        state.users = [.multiStoryUser, .secondUser]

        let store = TestStore(initialState: state) {
            StoryListFeature()
        }
        store.exhaustivity = .off

        await store.send(.userTapped(index: 0)) {
            $0.player = StoryPlayerFeature.State(
                allUsers: [.multiStoryUser, .secondUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        }
    }

    @Test
    func userTapStartsAtFirstUnseenStory() async {
        // Mark first story as seen via @Shared
        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        $seenIds.withLock { $0.insert("user1_photo1_0") }

        var state = StoryListFeature.State()
        state.users = [.multiStoryUser]

        let store = TestStore(initialState: state) {
            StoryListFeature()
        }
        store.exhaustivity = .off

        await store.send(.userTapped(index: 0)) {
            $0.player = StoryPlayerFeature.State(
                allUsers: [.multiStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 1 // skips story 0 (seen)
            )
        }
    }

    // MARK: - Pagination

    @Test
    func paginationTriggersNearEnd() async {
        var state = StoryListFeature.State()
        state.users = Array(repeating: User.singleStoryUser, count: 10)
        state.currentBlockIndex = 0

        let store = TestStore(initialState: state) {
            StoryListFeature()
        } withDependencies: {
            $0.pexelsClient.fetchCuratedPhotos = { _, _ in [] }
            $0.pexelsClient.fetchPopularVideos = { _, _ in [] }
            $0.persistenceClient.saveUsers = { _ in }
        }
        store.exhaustivity = .off

        // Index 8 is within 3 of count (10), should trigger pagination
        await store.send(.loadMoreIfNeeded(currentIndex: 8)) {
            $0.isLoading = true
        }
    }

    @Test
    func paginationDoesNotTriggerFarFromEnd() async {
        var state = StoryListFeature.State()
        state.users = Array(repeating: User.singleStoryUser, count: 10)
        state.currentBlockIndex = 0

        let store = TestStore(initialState: state) {
            StoryListFeature()
        }
        store.exhaustivity = .off

        // Index 3 is far from end — should not trigger
        await store.send(.loadMoreIfNeeded(currentIndex: 3))
        // No state change expected
    }

    // MARK: - Cache Bootstrap

    @Test
    func seenCacheLoadedPopulatesSharedState() async {
        let store = TestStore(initialState: StoryListFeature.State()) {
            StoryListFeature()
        }
        store.exhaustivity = .off

        let seenSet: Set<String> = ["story1", "story2"]
        await store.send(.seenCacheLoaded(seenSet))

        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        #expect(seenIds.contains("story1"))
        #expect(seenIds.contains("story2"))
    }

    @Test
    func likedCacheLoadedPopulatesSharedState() async {
        let store = TestStore(initialState: StoryListFeature.State()) {
            StoryListFeature()
        }
        store.exhaustivity = .off

        let likedSet: Set<String> = ["story3"]
        await store.send(.likedCacheLoaded(likedSet))

        @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
        #expect(likedIds.contains("story3"))
    }

    // MARK: - Refresh

    @Test
    func refreshWhenOfflineDoesNothing() async {
        var state = StoryListFeature.State()
        state.users = [.singleStoryUser]

        let store = TestStore(initialState: state) {
            StoryListFeature()
        } withDependencies: {
            $0.networkClient.isConnected = { false }
        }
        store.exhaustivity = .off

        await store.send(.refresh)
        // No state change — guard blocks when offline
    }
}
