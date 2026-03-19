import ComposableArchitecture
import UIKit

@DependencyClient
struct HapticClient: Sendable {
    var storyChanged: @Sendable () -> Void = { }
    var userChanged: @Sendable () -> Void = { }
    var liked: @Sendable () -> Void = { }
}

extension HapticClient: DependencyKey {
    static let liveValue = HapticClient(
        storyChanged: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        },
        userChanged: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        },
        liked: {
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
