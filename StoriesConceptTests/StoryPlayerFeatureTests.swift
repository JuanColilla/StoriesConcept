import ComposableArchitecture
import Foundation
import Testing

@testable import StoriesConcept

@Suite
@MainActor
struct StoryPlayerFeatureTests {

    // MARK: - Helper

    private func makeStore(
        users: [User] = [.multiStoryUser, .secondUser],
        userIndex: Int = 0,
        storyIndex: Int = 0,
        cacheAvailable: Bool = true
    ) -> TestStoreOf<StoryPlayerFeature> {
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: users,
                currentUserIndex: userIndex,
                currentStoryIndex: storyIndex
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { }
            $0.cacheClient.isAvailable = { _ in cacheAvailable }
            $0.cacheClient.load = { _ in nil }
            $0.cacheClient.save = { _, _, _ in }
            $0.persistenceClient.markSeen = { _ in }
            $0.persistenceClient.setLiked = { _, _ in }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        return store
    }

    // MARK: - Timer & Playback

    @Test
    func timerStartsOnAppear() async {
        let store = makeStore()

        // ImmediateClock fires all ticks instantly — the timer runs to completion
        // and emits storyCompleted + advances through all stories.
        // Use non-exhaustive to verify just the initial state change.
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isTimerRunning = true
        }
    }

    @Test
    func contentLoadingWhenNotCached() async {
        let store = makeStore(cacheAvailable: false)
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isContentLoading = true
            $0.isTimerRunning = false
        }
    }

    @Test
    func contentCheckResolvesWhenCached() async {
        let store = makeStore(cacheAvailable: true)
        store.exhaustivity = .off

        // Simulate the content check tick when cache has content
        await store.send(.contentCheckTick) {
            $0.isContentLoading = false
        }
    }

    @Test
    func longPressPausesTimer() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.send(.longPressStarted) {
            $0.isPaused = true
            $0.isTimerRunning = false
        }
    }

    @Test
    func longPressEndResumesTimer() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.send(.longPressStarted)

        await store.send(.longPressEnded) {
            $0.isPaused = false
        }
    }

    @Test
    func appBackgroundPausesTimer() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.send(.appBackgrounded) {
            $0.isPaused = true
            $0.isTimerRunning = false
        }
    }

    // MARK: - Navigation

    @Test
    func tappedRightAdvancesStory() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.tappedRight) {
            $0.currentStoryIndex = 1
            $0.progress = 0
        }
    }

    @Test
    func tappedRightMarksCurrentStorySeen() async {
        var seenIds: [String] = []
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: [.multiStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { }
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { id in seenIds.append(id) }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        await store.send(.tappedRight)

        // The FIRST story (index 0) should have been marked seen
        #expect(seenIds.contains("user1_photo1_0"))
    }

    @Test
    func tappedLeftRetreatsStory() async {
        let store = makeStore(storyIndex: 1)
        store.exhaustivity = .off

        await store.send(.tappedLeft) {
            $0.currentStoryIndex = 0
            $0.progress = 0
        }
    }

    @Test
    func tappedLeftAtFirstStoryDoesNothing() async {
        let store = makeStore(storyIndex: 0)
        store.exhaustivity = .off

        await store.send(.tappedLeft)
        // No state change expected
    }

    @Test
    func tappedRightAtLastStoryAdvancesUser() async {
        let store = makeStore(storyIndex: 2) // last story of multiStoryUser
        store.exhaustivity = .off

        await store.send(.tappedRight) {
            $0.currentUserIndex = 1
            $0.currentStoryIndex = 0
            $0.progress = 0
        }
    }

    @Test
    func swipeToNextUser() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.swipedToNextUser) {
            $0.currentUserIndex = 1
            $0.progress = 0
        }
    }

    @Test
    func swipeToPreviousUser() async {
        let store = makeStore(userIndex: 1)
        store.exhaustivity = .off

        await store.send(.swipedToPreviousUser) {
            $0.currentUserIndex = 0
            $0.currentStoryIndex = 0
            $0.progress = 0
        }
    }

    @Test
    func swipeDownDismisses() async {
        var dismissed = false
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: [.multiStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { dismissed = true }
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        await store.send(.swipedDown) {
            $0.isTimerRunning = false
        }

        #expect(dismissed)
    }

    @Test
    func lastUserAdvanceDismisses() async {
        var dismissed = false
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: [.singleStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { dismissed = true }
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        await store.send(.tappedRight)

        #expect(dismissed)
    }

    // MARK: - Like

    @Test
    func toggleLikeTogglesState() async {
        var likedIds: [(String, Bool)] = []
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: [.multiStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { }
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { _ in }
            $0.persistenceClient.setLiked = { id, liked in likedIds.append((id, liked)) }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        await store.send(.toggleLike) {
            $0.isLiked = true
        }

        #expect(likedIds.first?.0 == "user1_photo1_0")
        #expect(likedIds.first?.1 == true)

        await store.send(.toggleLike) {
            $0.isLiked = false
        }
    }

    // MARK: - Story Completed

    @Test
    func storyCompletedMarksSeen() async {
        var seenIds: [String] = []
        let store = TestStore(
            initialState: StoryPlayerFeature.State(
                allUsers: [.multiStoryUser],
                currentUserIndex: 0,
                currentStoryIndex: 0
            )
        ) {
            StoryPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dismiss = DismissEffect { }
            $0.cacheClient.isAvailable = { _ in true }
            $0.persistenceClient.markSeen = { id in seenIds.append(id) }
            $0.prefetchClient.prefetchStories = { _, _ in }
            $0.prefetchClient.cancelAll = { }
            $0.hapticClient.storyChanged = { }
            $0.hapticClient.userChanged = { }
            $0.hapticClient.liked = { }
        }
        store.exhaustivity = .off

        await store.send(.storyCompleted) {
            $0.currentStoryIndex = 1
            $0.progress = 0
        }

        #expect(seenIds.contains("user1_photo1_0"))
    }

    @Test
    func storyCompletedAdvancesToNextStory() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.storyCompleted) {
            $0.currentStoryIndex = 1
            $0.progress = 0
        }
    }
}
