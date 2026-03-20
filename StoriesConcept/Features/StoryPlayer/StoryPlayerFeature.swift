import ComposableArchitecture
import Foundation
import os
import Sharing

@Reducer
struct StoryPlayerFeature {
    enum CancelID { case timer, contentCheck, prefetch }
    @ObservableState
    struct State: Equatable {
        var allUsers: [User]
        var currentUserIndex: Int
        var currentStoryIndex: Int

        // Timer & playback
        var progress: Double = 0
        var isTimerRunning = false
        var isPaused = false
        var isContentLoading = false

        // Interaction
        var isLiked = false
        var shouldDismiss = false

        // Computed
        var currentUser: User { allUsers[currentUserIndex] }
        var currentStory: Story { currentUser.stories[currentStoryIndex] }
        var totalStories: Int { currentUser.stories.count }
        var isFirstStory: Bool { currentStoryIndex == 0 }
        var isLastUser: Bool { currentUserIndex >= allUsers.count - 1 }
    }

    enum Action {
        // User interactions
        case tappedRight
        case tappedLeft
        case swipedToNextUser
        case swipedToPreviousUser
        case swipedDown
        case toggleLike
        case longPressStarted
        case longPressEnded

        // Timer system
        case timerTick(Double)
        case storyCompleted

        // Content loading
        case contentCheckTick

        // Lifecycle
        case onAppear
        case onDisappear
        case appBackgrounded
        case appForegrounded

        // Delegate — communication to parent
        case delegate(Delegate)

        enum Delegate {
            case storySeen(String)
            case dismissed
        }
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.cacheClient) var cacheClient
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.prefetchClient) var prefetchClient
    @Dependency(\.hapticClient) var hapticClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // MARK: - Navigation

            case .tappedRight:
                return advanceStory(&state)

            case .tappedLeft:
                return retreatStory(&state)

            case .swipedToNextUser:
                return advanceUser(&state)

            case .swipedToPreviousUser:
                return retreatUser(&state)

            case .swipedDown:
                return dismiss(&state)

            // MARK: - Timer

            case .onAppear:
                return startPlayback(&state)

            case .timerTick(let elapsed):
                let duration = storyDuration(state.currentStory)
                state.progress = min(elapsed / duration, 1.0)
                return .none

            case .storyCompleted:
                return .merge(
                    markSeenEffect(state),
                    advanceStory(&state)
                )

            // MARK: - Interactions

            case .toggleLike:
                state.isLiked.toggle()
                let id = state.currentStory.id
                let liked = state.isLiked
                do {
                    @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
                    $likedIds.withLock {
                        if liked { $0.insert(id) } else { $0.remove(id) }
                    }
                }
                return .run { _ in
                    await hapticClient.liked()
                    try await persistenceClient.setLiked(id, liked)
                }

            case .longPressStarted:
                state.isPaused = true
                state.isTimerRunning = false
                return .cancel(id: CancelID.timer)

            case .longPressEnded:
                state.isPaused = false
                return startTimer(&state)

            // MARK: - Lifecycle

            case .appBackgrounded:
                state.isPaused = true
                state.isTimerRunning = false
                return .cancel(id: CancelID.timer)

            case .appForegrounded:
                guard !state.isPaused else { return .none }
                return startTimer(&state)

            case .onDisappear:
                state.isTimerRunning = false
                return .merge(
                    .cancel(id: CancelID.timer),
                    .cancel(id: CancelID.contentCheck),
                    .cancel(id: CancelID.prefetch)
                )

            // MARK: - Content loading

            case .contentCheckTick:
                let mediaId = state.currentStory.cacheKey
                if cacheClient.isAvailable(mediaId) {
                    state.isContentLoading = false
                    return .merge(
                        .cancel(id: CancelID.contentCheck),
                        startTimer(&state)
                    )
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Navigation Helpers

    private func advanceStory(_ state: inout State) -> Effect<Action> {
        let user = state.currentUser
        if state.currentStoryIndex < user.stories.count - 1 {
            state.currentStoryIndex += 1
            return onStoryChanged(&state, haptic: .story)
        } else {
            return advanceUser(&state)
        }
    }

    private func retreatStory(_ state: inout State) -> Effect<Action> {
        if state.currentStoryIndex > 0 {
            state.currentStoryIndex -= 1
            return onStoryChanged(&state, haptic: .story)
        }
        return .none
    }

    private func advanceUser(_ state: inout State) -> Effect<Action> {
        // Mark current as seen before advancing
        let seenEffect = markSeenEffect(state)

        if state.currentUserIndex < state.allUsers.count - 1 {
            state.currentUserIndex += 1
            let user = state.currentUser
            let storyIds = user.stories.map(\.id)
            @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
            state.currentStoryIndex = Self.firstUnseen(storyIds: storyIds, seenIds: seenIds)
            return .merge(seenEffect, onStoryChanged(&state, haptic: .user))
        } else {
            return .merge(seenEffect, dismiss(&state))
        }
    }

    private func retreatUser(_ state: inout State) -> Effect<Action> {
        if state.currentUserIndex > 0 {
            state.currentUserIndex -= 1
            state.currentStoryIndex = 0
            return onStoryChanged(&state, haptic: .user)
        }
        return .none
    }

    private func dismiss(_ state: inout State) -> Effect<Action> {
        state.shouldDismiss = true
        state.isTimerRunning = false
        return .merge(
            .cancel(id: CancelID.timer),
            .cancel(id: CancelID.contentCheck),
            .run { _ in prefetchClient.cancelAll() },
            .send(.delegate(.dismissed))
        )
    }

    // MARK: - Story Changed

    private enum HapticType { case story, user }

    private func onStoryChanged(_ state: inout State, haptic: HapticType) -> Effect<Action> {
        state.progress = 0
        do {
            @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
            state.isLiked = likedIds.contains(state.currentStory.id)
        }

        return .merge(
            .cancel(id: CancelID.timer),
            .cancel(id: CancelID.contentCheck),
            startPlayback(&state),
            .run { _ in
                switch haptic {
                case .story: await hapticClient.storyChanged()
                case .user: await hapticClient.userChanged()
                }
            },
            requestPrefetch(state)
        )
    }

    // MARK: - Playback

    private func startPlayback(_ state: inout State) -> Effect<Action> {
        let story = state.currentStory
        do {
            @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
            state.isLiked = likedIds.contains(story.id)
        }

        // Videos always stream, photos need cache check
        if story.type == .photo && !cacheClient.isAvailable(story.cacheKey) {
            state.isContentLoading = true
            state.isTimerRunning = false
            return startContentCheck()
        }

        state.isContentLoading = false
        return startTimer(&state)
    }

    // MARK: - Timer

    private func startTimer(_ state: inout State) -> Effect<Action> {
        guard !state.isPaused else { return .none }

        state.isTimerRunning = true
        let duration = storyDuration(state.currentStory)
        let startProgress = state.progress

        return .run { [clock] send in
            let startOffset = startProgress * duration
            var elapsed: Double = 0
            let interval: Duration = .milliseconds(16)

            for await _ in clock.timer(interval: interval) {
                elapsed += 0.016
                let total = startOffset + elapsed

                if total >= duration {
                    await send(.storyCompleted)
                    return
                }
                await send(.timerTick(total))
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func storyDuration(_ story: Story) -> Double {
        switch story.type {
        case .photo: return Constants.photoAutoAdvanceDuration
        case .video: return min(story.duration, Constants.maxVideoDuration)
        }
    }

    // MARK: - Content Loading

    private func startContentCheck() -> Effect<Action> {
        .run { send in
            // Poll every 0.5s for cache arrival
            for await _ in clock.timer(interval: .milliseconds(500)) {
                await send(.contentCheckTick)
            }
        }
        .cancellable(id: CancelID.contentCheck, cancelInFlight: true)
    }

    // MARK: - Seen/Liked

    private func markSeenEffect(_ state: State) -> Effect<Action> {
        let storyId = state.currentStory.id
        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        _ = $seenIds.withLock { $0.insert(storyId) }

        return .merge(
            .run { _ in
                try await persistenceClient.markSeen(storyId)
                Logger.player.info("Seen: \(storyId, privacy: .public)")
            },
            .send(.delegate(.storySeen(storyId)))
        )
    }

    // MARK: - Prefetch

    private func requestPrefetch(_ state: State) -> Effect<Action> {
        let current = state.currentUser
        let next = state.currentUserIndex + 1 < state.allUsers.count
            ? state.allUsers[state.currentUserIndex + 1]
            : nil

        return .run { _ in
            await prefetchClient.prefetchStories(current, next)
        }
        .cancellable(id: CancelID.prefetch, cancelInFlight: true)
    }

    // MARK: - Helpers

    static func firstUnseen(storyIds: [String], seenIds: Set<String>) -> Int {
        for (index, id) in storyIds.enumerated() {
            if !seenIds.contains(id) { return index }
        }
        return 0
    }
}
