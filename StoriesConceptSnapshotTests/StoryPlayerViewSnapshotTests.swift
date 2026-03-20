import ComposableArchitecture
import Sharing
import SnapshotTesting
import SwiftUI
import Testing

@testable import StoriesConcept

@Suite("StoryPlayerView Snapshots", .snapshots(record: .missing))
@MainActor
struct StoryPlayerViewSnapshotTests {

    /// Creates a Store for StoryPlayerFeature with all deps stubbed (no side effects).
    private func makePlayerStore(
        users: [User] = [.snapshotMultiStory, .snapshotSecondUser],
        userIndex: Int = 0,
        storyIndex: Int = 0,
        progress: Double = 0,
        isLiked: Bool = false,
        isContentLoading: Bool = false,
        isPaused: Bool = false
    ) -> StoreOf<StoryPlayerFeature> {
        var state = StoryPlayerFeature.State(
            allUsers: users,
            currentUserIndex: userIndex,
            currentStoryIndex: storyIndex
        )
        state.progress = progress
        state.isLiked = isLiked
        state.isContentLoading = isContentLoading
        state.isPaused = isPaused

        return Store(initialState: state) {
            EmptyReducer<StoryPlayerFeature.State, StoryPlayerFeature.Action>()
        }
    }

    // MARK: - Default State (photo, no progress)

    @Test(arguments: AppearanceMode.allCases)
    func defaultState(_ mode: AppearanceMode) {
        let store = makePlayerStore()
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "default_\(mode.rawValue)")
    }

    // MARK: - Mid-Progress

    @Test(arguments: AppearanceMode.allCases)
    func midProgress(_ mode: AppearanceMode) {
        let store = makePlayerStore(storyIndex: 1, progress: 0.6)
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "midProgress_\(mode.rawValue)")
    }

    // MARK: - Liked State

    @Test(arguments: AppearanceMode.allCases)
    func liked(_ mode: AppearanceMode) {
        let store = makePlayerStore(progress: 0.3, isLiked: true)
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "liked_\(mode.rawValue)")
    }

    // MARK: - Content Loading

    @Test(arguments: AppearanceMode.allCases)
    func contentLoading(_ mode: AppearanceMode) {
        let store = makePlayerStore(isContentLoading: true)
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "contentLoading_\(mode.rawValue)")
    }

    // MARK: - Last Story of User

    @Test(arguments: AppearanceMode.allCases)
    func lastStory(_ mode: AppearanceMode) {
        let store = makePlayerStore(storyIndex: 2, progress: 0.9)
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "lastStory_\(mode.rawValue)")
    }

    // MARK: - Second User

    @Test(arguments: AppearanceMode.allCases)
    func secondUser(_ mode: AppearanceMode) {
        let store = makePlayerStore(userIndex: 1, storyIndex: 0, progress: 0.4)
        let view = StoryPlayerView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "secondUser_\(mode.rawValue)")
    }
}
