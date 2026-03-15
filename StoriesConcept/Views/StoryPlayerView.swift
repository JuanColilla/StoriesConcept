import SwiftUI

struct StoryPlayerView: View {
    @State var viewModel: StoryPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @GestureState private var isLongPressing = false
    /// Suppresses tap gestures briefly after a long press ends.
    /// Without this, the finger-up from a hold triggers onTapGesture.
    @State private var suppressTap = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = viewModel.currentStory {
                // Content layer
                contentView(for: story)
                    .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }

                // Tap zones (left = previous, right = next) — BELOW UI overlay
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !suppressTap else { return }
                            viewModel.previousStory()
                        }

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !suppressTap else { return }
                            viewModel.nextStory()
                        }
                }
                .ignoresSafeArea()

                // UI overlay — ON TOP of tap zones so buttons are tappable
                VStack(spacing: 0) {
                    topOverlay
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .statusBarHidden()
        .gesture(dragGesture)
        .gesture(longPressGesture)
        .onChange(of: isLongPressing) { _, pressing in
            if pressing {
                viewModel.pauseTimer()
            } else {
                viewModel.resumeTimer()
                // Briefly suppress taps so the finger-up from the hold
                // doesn't trigger onTapGesture (next/previous story).
                suppressTap = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressTap = false
                }
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .onAppear {
            viewModel.startTimer()
        }
        .onDisappear {
            viewModel.stopTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.pauseTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.resumeTimer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(for story: Story) -> some View {
        // .id(story.id) forces SwiftUI to destroy and recreate the view when
        // the story changes, rather than reusing the existing instance.
        // Critical for VideoPlayerView: without this, updateUIViewController
        // is called instead of makeUIViewController, so the old AVPlayer
        // keeps playing the previous video.
        Group {
            switch story.type {
            case .photo:
                if let data = viewModel.imageData(for: story),
                   let uiImage = downsampledImage(data: data) {
                    Color.black
                        .overlay {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                } else {
                    Color.black
                }
            case .video:
                VideoPlayerView(
                    url: story.mediaURL,
                    isPaused: viewModel.isPaused,
                    onBufferingChanged: { isBuffering in
                        viewModel.isVideoBuffering = isBuffering
                    }
                )
                .ignoresSafeArea()
            }
        }
        .id(story.id)
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack(spacing: 8) {
            // Progress bar
            StoryProgressBar(
                totalSegments: viewModel.totalStories,
                activeIndex: viewModel.currentStoryIndex,
                activeProgress: viewModel.progress,
                isSeenAt: { viewModel.isStorySeen(at: $0) }
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // User info + close
            HStack(spacing: 10) {
                if let user = viewModel.currentUser {
                    AsyncImage(url: user.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.5))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        if let story = viewModel.currentStory {
                            Text(story.postedAt.timeAgoDisplay())
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        HStack {
            Spacer()

            Button {
                viewModel.toggleLike()
            } label: {
                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(viewModel.isLiked ? .red : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.trailing, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Gestures (separated for reliability)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: Constants.dragMinDistance)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(vertical) > abs(horizontal) && vertical > 50 {
                    viewModel.dismiss()
                } else if abs(horizontal) > abs(vertical) {
                    if horizontal < -50 {
                        viewModel.nextUser()
                    } else if horizontal > 50 {
                        viewModel.previousUser()
                    }
                }
            }
    }

    private var longPressGesture: some Gesture {
        // Sequenced gesture: LongPress recognizes after 0.15s, then a zero-distance
        // DragGesture keeps the gesture alive while the finger stays on screen.
        // Without the drag sequel, LongPressGesture is discrete — it completes
        // after recognition and @GestureState resets immediately.
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isLongPressing) { value, state, _ in
                switch value {
                case .second(true, _):
                    // Long press recognized AND finger still held down
                    state = true
                default:
                    break
                }
            }
    }

    // MARK: - Image Processing

    private func downsampledImage(data: Data) -> UIImage? {
        let screenScale = UITraitCollection.current.displayScale
        let maxPixelSize = 2560.0 * max(screenScale, 2.0) // Safe upper bound for any device
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let interval = Date().timeIntervalSince(self)
        let hours = Int(interval / 3600)
        if hours < 1 { return "Just now" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
