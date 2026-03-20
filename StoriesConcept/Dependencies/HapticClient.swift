import ComposableArchitecture
import UIKit

@DependencyClient
struct HapticClient: Sendable {
    var storyChanged: @Sendable () async -> Void
    var userChanged: @Sendable () async -> Void
    var liked: @Sendable () async -> Void
}

extension HapticClient: DependencyKey {
    static let liveValue = HapticClient(
        storyChanged: { @MainActor in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        },
        userChanged: { @MainActor in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        },
        liked: { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    )

    static let previewValue = HapticClient()
}

extension DependencyValues {
    var hapticClient: HapticClient {
        get { self[HapticClient.self] }
        set { self[HapticClient.self] = newValue }
    }
}
