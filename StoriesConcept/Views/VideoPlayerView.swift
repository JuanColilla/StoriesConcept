import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let isPaused: Bool
    /// Reports buffering state changes back to the parent.
    /// `true` = video is buffering/not yet playing, `false` = video is actively playing.
    var onBufferingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        // Activate audio session so video sound plays through the speaker,
        // even when the silent switch is on (matches Instagram Stories behavior).
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        controller.player = player

        // Start observing timeControlStatus to detect when playback actually begins.
        // AVPlayer transitions: .waitingToPlayAtCurrentRate → .playing once buffered.
        context.coordinator.observe(player: player, onBufferingChanged: onBufferingChanged)

        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // Keep the coordinator's callback in sync — SwiftUI may recreate the
        // closure on each body evaluation, but the coordinator persists.
        context.coordinator.onBufferingChanged = onBufferingChanged

        if isPaused {
            controller.player?.pause()
        } else {
            if controller.player?.rate == 0 {
                controller.player?.play()
            }
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.invalidate()
        controller.player?.pause()
        controller.player = nil
    }

    // MARK: - Coordinator (KVO on AVPlayer.timeControlStatus)

    class Coordinator: NSObject {
        var onBufferingChanged: ((Bool) -> Void)?
        private var observation: NSKeyValueObservation?

        /// Observes the player's `timeControlStatus` to detect buffering vs playing.
        func observe(player: AVPlayer, onBufferingChanged: ((Bool) -> Void)?) {
            self.onBufferingChanged = onBufferingChanged

            // Assume buffering until proven otherwise
            onBufferingChanged?(true)

            observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let callback = self?.onBufferingChanged
                Task { @MainActor in
                    let isBuffering = player.timeControlStatus != .playing
                    callback?(isBuffering)
                }
            }
        }

        func invalidate() {
            observation?.invalidate()
            observation = nil
        }
    }
}
