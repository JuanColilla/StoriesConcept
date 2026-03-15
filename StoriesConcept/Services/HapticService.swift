import UIKit

@Observable
final class HapticService {
    func storyChanged() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func userChanged() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func liked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
