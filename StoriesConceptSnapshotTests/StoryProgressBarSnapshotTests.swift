import SnapshotTesting
import SwiftUI
import Testing

@testable import StoriesConcept

@Suite("StoryProgressBar Snapshots", .snapshots(record: .missing))
@MainActor
struct StoryProgressBarSnapshotTests {

    /// Progress bar renders white on transparent — wrap in dark background for visibility.
    private func progressBarView(
        total: Int,
        active: Int,
        progress: Double
    ) -> some View {
        StoryProgressBar(
            totalSegments: total,
            activeIndex: active,
            activeProgress: progress,
            isSeenAt: { _ in false }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .background(Color.black)
    }

    // MARK: - Beginning (first segment, no progress)

    @Test(arguments: AppearanceMode.allCases)
    func beginning(_ mode: AppearanceMode) {
        let view = progressBarView(total: 5, active: 0, progress: 0)
        let vc = hostComponent(view, colorScheme: mode.colorScheme, height: 48)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "beginning_\(mode.rawValue)")
    }

    // MARK: - Mid-Progress (third segment at 50%)

    @Test(arguments: AppearanceMode.allCases)
    func midProgress(_ mode: AppearanceMode) {
        let view = progressBarView(total: 5, active: 2, progress: 0.5)
        let vc = hostComponent(view, colorScheme: mode.colorScheme, height: 48)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "midProgress_\(mode.rawValue)")
    }

    // MARK: - Near End (last segment at 80%)

    @Test(arguments: AppearanceMode.allCases)
    func nearEnd(_ mode: AppearanceMode) {
        let view = progressBarView(total: 5, active: 4, progress: 0.8)
        let vc = hostComponent(view, colorScheme: mode.colorScheme, height: 48)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "nearEnd_\(mode.rawValue)")
    }

    // MARK: - Single Segment

    @Test(arguments: AppearanceMode.allCases)
    func singleSegment(_ mode: AppearanceMode) {
        let view = progressBarView(total: 1, active: 0, progress: 0.6)
        let vc = hostComponent(view, colorScheme: mode.colorScheme, height: 48)
        assertSnapshot(of: vc, as: .image(precision: 0.99), named: "singleSegment_\(mode.rawValue)")
    }
}
