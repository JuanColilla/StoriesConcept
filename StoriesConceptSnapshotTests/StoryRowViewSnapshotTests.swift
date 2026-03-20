import SnapshotTesting
import SwiftUI
import Testing

@testable import StoriesConcept

@Suite("StoryRowView Snapshots", .snapshots(record: .missing))
@MainActor
struct StoryRowViewSnapshotTests {

    // MARK: - Unseen Stories

    @Test(arguments: AppearanceMode.allCases)
    func unseenStories(_ mode: AppearanceMode) {
        let view = StoryRowView(
            user: .snapshotMultiStory,
            unseenCount: 3,
            allSeen: false
        )
        .padding(.horizontal, 16)

        let vc = hostComponent(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "unseen_\(mode.rawValue)")
    }

    // MARK: - All Seen

    @Test(arguments: AppearanceMode.allCases)
    func allSeen(_ mode: AppearanceMode) {
        let view = StoryRowView(
            user: .snapshotSingleStory,
            unseenCount: 0,
            allSeen: true
        )
        .padding(.horizontal, 16)

        let vc = hostComponent(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "allSeen_\(mode.rawValue)")
    }

    // MARK: - Single Unseen

    @Test(arguments: AppearanceMode.allCases)
    func singleUnseen(_ mode: AppearanceMode) {
        let view = StoryRowView(
            user: .snapshotSecondUser,
            unseenCount: 1,
            allSeen: false
        )
        .padding(.horizontal, 16)

        let vc = hostComponent(view, colorScheme: mode.colorScheme)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "singleUnseen_\(mode.rawValue)")
    }
}
