import Foundation

@Observable
@MainActor
final class StoryListViewModel {
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?

    // Internal access — StoryListView passes these to StoryPlayerViewModel
    let pexelsService: PexelsService
    let cacheService: CacheService
    let persistenceService: PersistenceService
    let prefetchService: PrefetchService
    let networkMonitor: NetworkMonitor

    private var currentBlockIndex = -1
    private var isLoadingMore = false

    // Content pools for recycling
    private var photoPool: [PexelsPhoto] = []
    private var videoPool: [PexelsVideo] = []
    private var avatarPool: [PexelsPhoto] = []

    init(
        pexelsService: PexelsService,
        cacheService: CacheService,
        persistenceService: PersistenceService,
        prefetchService: PrefetchService,
        networkMonitor: NetworkMonitor
    ) {
        self.pexelsService = pexelsService
        self.cacheService = cacheService
        self.persistenceService = persistenceService
        self.prefetchService = prefetchService
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public

    func loadInitial() async {
        isLoading = true
        errorMessage = nil

        // Check for persisted users first
        let persisted = persistenceService.fetchAllUsers()
        if !persisted.isEmpty {
            users = persisted.map { UserGenerator.toDomainUser($0) }
            currentBlockIndex = persistenceService.maxBlockIndex()
            isLoading = false
            return
        }

        // First launch — fetch from API
        do {
            try await fetchContentPool(page: 1)
            try await fetchAvatars()
            generateBlock(index: 0)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func loadMoreIfNeeded(currentUser: User) {
        // Legacy entry point — kept for StoryPlayerViewModel's loadMoreCallback.
        // Falls back to O(n) scan only when called without an index.
        guard let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return }
        loadMoreIfNeeded(currentIndex: index)
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        // Trigger when within last 3 users — O(1) check
        guard currentIndex >= users.count - 3,
              !isLoadingMore else { return }

        Task { await loadMore() }
    }

    func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        let nextBlock = currentBlockIndex + 1

        if nextBlock <= 1 {
            // Blocks 0-1: fetch new content from API
            do {
                try await fetchContentPool(page: nextBlock + 1)
                if avatarPool.isEmpty { try await fetchAvatars() }
                generateBlock(index: nextBlock)
            } catch {
                // Silently fail — existing content remains
            }
        } else {
            // Block 2+: recycle content, no API calls.
            // If pools are empty (app re-launched from persistence), refetch
            // content so recycled blocks have material to work with.
            if photoPool.isEmpty && videoPool.isEmpty {
                do {
                    try await fetchContentPool(page: 1)
                    if avatarPool.isEmpty { try await fetchAvatars() }
                } catch {
                    isLoadingMore = false
                    return
                }
            }
            generateBlock(index: nextBlock)
        }

        isLoadingMore = false
    }

    func retry() async {
        await loadInitial()
    }

    /// Pull-to-refresh: fetches fresh content from the API and generates
    /// a new block of users, prepended to the list so they appear at the top.
    func refresh() async {
        guard networkMonitor.isConnected else { return }

        do {
            try await fetchContentPool(page: Int.random(in: 1...2))
            if avatarPool.isEmpty { try await fetchAvatars() }
        } catch {
            return
        }

        let nextBlock = currentBlockIndex + 1
        let previousCount = users.count
        generateBlock(index: nextBlock)

        // Move newly appended users to the top so they're visible immediately
        let newUsers = Array(users[previousCount...])
        users.removeSubrange(previousCount...)
        users.insert(contentsOf: newUsers, at: 0)
    }

    func unseenCount(for user: User) -> Int {
        persistenceService.unseenCount(storyIds: user.stories.map(\.id))
    }

    func allSeen(for user: User) -> Bool {
        persistenceService.allSeen(storyIds: user.stories.map(\.id))
    }

    func firstUnseenIndex(for user: User) -> Int {
        persistenceService.firstUnseenIndex(storyIds: user.stories.map(\.id))
    }

    func requestThumbnailPrefetch(for visibleUsers: [User]) {
        prefetchService.prefetchThumbnails(for: visibleUsers)
    }

    // MARK: - Content Fetching

    private func fetchContentPool(page: Int) async throws {
        async let photos = pexelsService.fetchCuratedPhotos(page: page)
        async let videos = pexelsService.fetchPopularVideos(page: page)

        let (photoResponse, videoResponse) = try await (photos, videos)
        photoPool.append(contentsOf: photoResponse.photos)
        videoPool.append(contentsOf: videoResponse.videos)
    }

    private func fetchAvatars() async throws {
        let response = try await pexelsService.fetchAvatarPhotos()
        avatarPool = response.photos
    }

    // MARK: - User Generation

    private func generateBlock(index: Int) {
        let result = UserGenerator.generate(
            blockIndex: index,
            photos: photoPool,
            videos: videoPool,
            avatars: avatarPool
        )

        persistenceService.saveUsers(result.persisted)
        users.append(contentsOf: result.users)
        currentBlockIndex = index
    }
}
