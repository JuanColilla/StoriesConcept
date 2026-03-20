import ComposableArchitecture
import Foundation
import Testing

@testable import StoriesConcept

@Suite
@MainActor
struct StoryFlowIntegrationTests {

    // MARK: - Full Viewing Flow

    @Test
    func viewAllStoriesThenDismissUpdatesBadges() async {
        // Setup: user with 2 stories, player opens at story 0
        var listState = StoryListFeature.State()
        listState.users = [.multiStoryUser, .secondUser]

        let store = TestStore(initialState: listState) {
            StoryListFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        // 1. Tap first user → player opens
        await store.send(.userTapped(index: 0)) {
            $0.player = StoryPlayerFeature.State(
                allUsers: [.multiStoryUser, .secondUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        }

        // 2. Tap right through stories (marks each as seen)
        await store.send(.player(.presented(.tappedRight)))
        await store.send(.player(.presented(.tappedRight)))
        // Story 2 (last) → tappedRight advances to next user
        await store.send(.player(.presented(.tappedRight)))

        // 3. Verify seen state was updated via @Shared
        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        #expect(seenIds.contains("user1_photo1_0"))
        #expect(seenIds.contains("user1_photo2_0"))
        #expect(seenIds.contains("user1_video1_0"))
    }

    // MARK: - Like Flow

    @Test
    func likeStoryPersistsAcrossFeatures() async {
        var listState = StoryListFeature.State()
        listState.users = [.multiStoryUser]

        var likedPersisted = false
        let store = TestStore(initialState: listState) {
            StoryListFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.persistenceClient.setLiked = { _, liked in likedPersisted = liked }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        // Open player
        await store.send(.userTapped(index: 0))

        // Like story
        await store.send(.player(.presented(.toggleLike)))

        // Verify like was persisted
        #expect(likedPersisted)

        // Verify @Shared state updated
        @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
        #expect(likedIds.contains("user1_photo1_0"))
    }

    // MARK: - Seen State Sync

    @Test
    func seenStateSyncsFromPlayerToList() async {
        var listState = StoryListFeature.State()
        listState.users = [.singleStoryUser]

        let store = TestStore(initialState: listState) {
            StoryListFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        // Open player → story is the only one → tappedRight will dismiss
        await store.send(.userTapped(index: 0))

        // The storySeen delegate should fire when user advances past the single story
        await store.send(.player(.presented(.tappedRight)))

        // The @Shared seenIds should now contain the story
        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        #expect(seenIds.contains("user1_photo1_0"))
    }
}
