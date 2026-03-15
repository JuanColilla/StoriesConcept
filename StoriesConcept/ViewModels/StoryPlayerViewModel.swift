import Foundation
import Combine

@Observable
@MainActor
final class StoryPlayerViewModel {
    // MARK: - Published State
    var currentStoryIndex: Int = 0
    var currentUserIndex: Int = 0
    var progress: Double = 0
    var isLiked: Bool = false
    var isLoading: Bool = false
    var isPaused: Bool = false
    var shouldDismiss: Bool = false

    var currentStory: Story? {
        guard currentUserIndex < allUsers.count else { return nil }
        let user = allUsers[currentUserIndex]
        guard currentStoryIndex < user.stories.count else { return nil }
        return user.stories[currentStoryIndex]
    }

    var currentUser: User? {
        guard currentUserIndex < allUsers.count else { return nil }
        return allUsers[currentUserIndex]
    }

    var totalStories: Int {
        currentUser?.stories.count ?? 0
    }

    // MARK: - Dependencies
    private let persistenceService: PersistenceService
    private let cacheService: CacheService
    private let prefetchService: PrefetchService
    private let hapticService: HapticService
    private(set) var allUsers: [User]
    private let loadMoreCallback: ((User) -> Void)?

    private var timer: Timer?
    private var loadingCheckTimer: Timer?
    private var timerStartDate: Date?
    private var elapsedBeforePause: TimeInterval = 0

    init(
        users: [User],
        initialUserIndex: Int,
        initialStoryIndex: Int,
        persistenceService: PersistenceService,
        cacheService: CacheService,
        prefetchService: PrefetchService,
        hapticService: HapticService,
        loadMoreCallback: ((User) -> Void)? = nil
    ) {
        self.allUsers = users
        self.currentUserIndex = initialUserIndex
        self.currentStoryIndex = initialStoryIndex
        self.persistenceService = persistenceService
        self.cacheService = cacheService
        self.prefetchService = prefetchService
        self.hapticService = hapticService
        self.loadMoreCallback = loadMoreCallback

        updateLikedState()
        checkContentLoaded()
        requestPrefetch()
    }

    // MARK: - Navigation

    func nextStory() {
        guard let user = currentUser else { return }

        // Mark current story as seen (completed by advancing)
        markCurrentSeen()

        if currentStoryIndex < user.stories.count - 1 {
            currentStoryIndex += 1
            hapticService.storyChanged()
            onStoryChanged()
        } else {
            nextUser()
        }
    }

    func previousStory() {
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            hapticService.storyChanged()
            onStoryChanged()
        }
        // If first story, do nothing (no wrap)
    }

    func nextUser() {
        // Mark current story as seen before advancing
        markCurrentSeen()

        if currentUserIndex < allUsers.count - 1 {
            currentUserIndex += 1
            currentStoryIndex = persistenceService.firstUnseenIndex(
                storyIds: allUsers[currentUserIndex].stories.map(\.id)
            )
            hapticService.userChanged()
            onStoryChanged()
            requestPrefetch()

            // Check if we need more users
            if let user = currentUser {
                loadMoreCallback?(user)
            }
        } else {
            // Last user — try to load more
            if let user = currentUser {
                loadMoreCallback?(user)
            }
            shouldDismiss = true
        }
    }

    func previousUser() {
        if currentUserIndex > 0 {
            currentUserIndex -= 1
            currentStoryIndex = 0
            hapticService.userChanged()
            onStoryChanged()
            requestPrefetch()
        }
    }

    func toggleLike() {
        guard let story = currentStory else { return }
        isLiked.toggle()
        persistenceService.setLiked(storyId: story.id, liked: isLiked)
        hapticService.liked()
    }

    func dismiss() {
        stopTimer()
        prefetchService.cancelAll()
        shouldDismiss = true
    }

    // MARK: - Timer Control

    func startTimer() {
        guard let story = currentStory, !isPaused else { return }

        // Check if content is loaded
        if !isContentAvailable(story: story) {
            isLoading = true
            startLoadingCheck()
            return
        }

        isLoading = false
        timerStartDate = Date()

        let remainingDuration = story.duration - elapsedBeforePause
        guard remainingDuration > 0 else {
            timerCompleted()
            return
        }

        // Update progress at 60fps
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    func pauseTimer() {
        isPaused = true
        if let startDate = timerStartDate {
            elapsedBeforePause += Date().timeIntervalSince(startDate)
        }
        timer?.invalidate()
        timer = nil
    }

    func resumeTimer() {
        isPaused = false
        startTimer()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        loadingCheckTimer?.invalidate()
        loadingCheckTimer = nil
        timerStartDate = nil
        elapsedBeforePause = 0
    }

    // MARK: - Content

    func imageData(for story: Story) -> Data? {
        cacheService.load(mediaId: story.cacheKey)
    }

    func updateUsers(_ users: [User]) {
        self.allUsers = users
    }

    // MARK: - Seen State Queries (for progress bar)

    func isStorySeen(at index: Int) -> Bool {
        guard let user = currentUser, index < user.stories.count else { return false }
        return persistenceService.isSeen(storyId: user.stories[index].id)
    }

    // MARK: - Private

    private func onStoryChanged() {
        stopTimer()
        progress = 0
        updateLikedState()
        checkContentLoaded()
        startTimer()
    }

    private func updateLikedState() {
        guard let story = currentStory else { return }
        isLiked = persistenceService.isLiked(storyId: story.id)
    }

    private func checkContentLoaded() {
        guard let story = currentStory else { return }
        isLoading = !isContentAvailable(story: story)
    }

    private func isContentAvailable(story: Story) -> Bool {
        // Videos stream from URL, no need to pre-cache the video data
        if story.type == .video { return true }
        return cacheService.isAvailable(mediaId: story.cacheKey)
    }

    private func updateProgress() {
        guard let story = currentStory, let startDate = timerStartDate else { return }
        let elapsed = elapsedBeforePause + Date().timeIntervalSince(startDate)
        progress = min(elapsed / story.duration, 1.0)

        if progress >= 1.0 {
            timerCompleted()
        }
    }

    private func timerCompleted() {
        stopTimer()
        progress = 1.0
        markCurrentSeen()

        // Auto-advance
        if let user = currentUser, currentStoryIndex < user.stories.count - 1 {
            currentStoryIndex += 1
            hapticService.storyChanged()
            onStoryChanged()
        } else {
            nextUser()
        }
    }

    private func markCurrentSeen() {
        guard let story = currentStory else { return }
        persistenceService.markSeen(storyId: story.id)
    }

    private func requestPrefetch() {
        guard let current = currentUser else { return }
        let next = currentUserIndex + 1 < allUsers.count ? allUsers[currentUserIndex + 1] : nil
        prefetchService.prefetchStories(currentUser: current, nextUser: next)
    }

    private func startLoadingCheck() {
        loadingCheckTimer?.invalidate()
        // Poll every 0.5s to check if content has been cached
        loadingCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] checkTimer in
            Task { @MainActor in
                guard let self, let story = self.currentStory else {
                    checkTimer.invalidate()
                    return
                }
                if self.isContentAvailable(story: story) {
                    checkTimer.invalidate()
                    self.isLoading = false
                    self.startTimer()
                }
            }
        }
    }
}
