import ComposableArchitecture
import Sharing
import SwiftUI

struct StoryPlayerView: View {
    @Bindable var store: StoreOf<StoryPlayerFeature>
    @Environment(\.dismiss) private var dismiss
    @GestureState private var isLongPressing = false
    /// Suppresses tap gestures briefly after a long press ends.
    /// Without this, the finger-up from a hold triggers onTapGesture.
    @State private var suppressTap = false

    @SharedReader(.inMemory("seenIds")) var seenIds: Set<String> = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Content layer
            contentView(for: store.currentStory)
                .ignoresSafeArea()

            // Loading overlay
            if store.isContentLoading {
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
                        store.send(.tappedLeft)
                    }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !suppressTap else { return }
                        store.send(.tappedRight)
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
        .statusBarHidden()
        .gesture(dragGesture)
        .gesture(longPressGesture)
        .onChange(of: isLongPressing) { _, pressing in
            if pressing {
                store.send(.longPressStarted)
            } else {
                store.send(.longPressEnded)
                // Briefly suppress taps so the finger-up from the hold
                // doesn't trigger onTapGesture (next/previous story).
                suppressTap = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressTap = false
                }
            }
        }
        .onChange(of: store.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            store.send(.appBackgrounded)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            store.send(.appForegrounded)
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
                PhotoContentView(story: story)
            case .video:
                VideoPlayerView(
                    url: story.mediaURL,
                    isPaused: store.isPaused,
                    onBufferingChanged: nil
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
                totalSegments: store.totalStories,
                activeIndex: store.currentStoryIndex,
                activeProgress: store.progress,
                isSeenAt: { index in
                    let story = store.currentUser.stories[index]
                    return seenIds.contains(story.id)
                }
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // User info + close
            HStack(spacing: 10) {
                let user = store.currentUser

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

                    Text(store.currentStory.postedAt.timeAgoDisplay())
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    store.send(.swipedDown)
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
                store.send(.toggleLike)
            } label: {
                Image(systemName: store.isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(store.isLiked ? .red : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.trailing, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: Constants.dragMinDistance)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(vertical) > abs(horizontal) && vertical > 50 {
                    store.send(.swipedDown)
                } else if abs(horizontal) > abs(vertical) {
                    if horizontal < -50 {
                        store.send(.swipedToNextUser)
                    } else if horizontal > 50 {
                        store.send(.swipedToPreviousUser)
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
}

// MARK: - Photo Content View

private struct PhotoContentView: View {
    let story: Story
    @State private var imageData: Data?
    @Dependency(\.cacheClient) var cacheClient

    var body: some View {
        Group {
            if let data = imageData,
               let uiImage = Self.downsampledImage(data: data) {
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
        }
        .task {
            imageData = await cacheClient.load(story.cacheKey)
        }
    }

    private static func downsampledImage(data: Data) -> UIImage? {
        let screenScale = UITraitCollection.current.displayScale
        let maxPixelSize = 2560.0 * max(screenScale, 2.0)
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
