import ComposableArchitecture
import Sharing
import SnapshotTesting
import SwiftUI
import Testing

@testable import StoriesConcept

@Suite("StoryListView Snapshots", .snapshots(record: .missing))
@MainActor
struct StoryListViewSnapshotTests {

    // MARK: - Loading State

    @Test(arguments: AppearanceMode.allCases)
    func loading(_ mode: AppearanceMode) {
        var state = StoryListFeature.State()
        state.isLoading = true

        let store = Store(initialState: state) {
            EmptyReducer<StoryListFeature.State, StoryListFeature.Action>()
        }

        let view = StoryListView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "loading_\(mode.rawValue)")
    }

    // MARK: - Error State

    @Test(arguments: AppearanceMode.allCases)
    func error(_ mode: AppearanceMode) {
        var state = StoryListFeature.State()
        state.errorMessage = "Network error"

        let store = Store(initialState: state) {
            EmptyReducer<StoryListFeature.State, StoryListFeature.Action>()
        }

        let view = StoryListView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "error_\(mode.rawValue)")
    }

    // MARK: - Populated (all unseen)

    @Test(arguments: AppearanceMode.allCases)
    func populatedUnseen(_ mode: AppearanceMode) {
        var state = StoryListFeature.State()
        state.users = [.snapshotMultiStory, .snapshotSecondUser, .snapshotThirdUser]

        let store = Store(initialState: state) {
            EmptyReducer<StoryListFeature.State, StoryListFeature.Action>()
        }

        let view = StoryListView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "populated_unseen_\(mode.rawValue)")
    }

    // MARK: - Populated (mixed seen/unseen)

    @Test(arguments: AppearanceMode.allCases)
    func populatedMixed(_ mode: AppearanceMode) {
        @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
        $seenIds.withLock {
            $0.insert("user1_photo1_0")
            $0.insert("user1_photo2_0")
            $0.insert("user1_video1_0")
        }

        var state = StoryListFeature.State()
        state.users = [.snapshotMultiStory, .snapshotSecondUser, .snapshotThirdUser]

        let store = Store(initialState: state) {
            EmptyReducer<StoryListFeature.State, StoryListFeature.Action>()
        }

        let view = StoryListView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "populated_mixed_\(mode.rawValue)")

        $seenIds.withLock { $0.removeAll() }
    }

    // MARK: - Empty List

    @Test(arguments: AppearanceMode.allCases)
    func emptyList(_ mode: AppearanceMode) {
        let state = StoryListFeature.State()

        let store = Store(initialState: state) {
            EmptyReducer<StoryListFeature.State, StoryListFeature.Action>()
        }

        let view = StoryListView(store: store)
        let vc = hostView(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "empty_\(mode.rawValue)")
    }
}
