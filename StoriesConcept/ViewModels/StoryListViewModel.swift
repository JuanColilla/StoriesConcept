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
        prefetchService: PrefetchService
    ) {
        self.pexelsService = pexelsService
        self.cacheService = cacheService
        self.persistenceService = persistenceService
        self.prefetchService = prefetchService
    }

    // MARK: - Public

    func loadInitial() async {
        isLoading = true
        errorMessage = nil

        // Check for persisted users first
        let persisted = persistenceService.fetchAllUsers()
        if !persisted.isEmpty {
            users = persisted.map { toDomainUser($0) }
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
        var usedNames: Set<String> = []
        var newUsers: [User] = []
        var persistedUsers: [PersistedUser] = []

        // Shuffle pools and use rotating indices to maximize content variety.
        // randomElement() causes frequent collisions (birthday paradox) when
        // pool size (~15-30) is close to total stories assigned (~10-100).
        // Rotating through a shuffled copy guarantees every item is used
        // before any repetition, while still wrapping around for blocks
        // that need more stories than pool size (block 2+ recycling).
        let shuffledPhotos = photoPool.shuffled()
        let shuffledVideos = videoPool.shuffled()
        var photoIdx = 0
        var videoIdx = 0

        for _ in 0..<Constants.usersPerBlock {
            // Pick unique name within block
            var name: String
            repeat {
                let baseName = Constants.namePool.randomElement()!
                let suffix = Int.random(in: 10...9999)
                name = "\(baseName)_\(suffix)"
            } while usedNames.contains(name)
            usedNames.insert(name)

            let userId = name

            // Pick avatar
            let avatar = avatarPool.randomElement()
            let avatarURLString = avatar?.src.medium ?? "https://via.placeholder.com/100"
            let avatarURL = URL(string: avatarURLString)!

            // Assign random number of stories (1-10)
            let storyCount = Int.random(in: Constants.minStoriesPerUser...Constants.maxStoriesPerUser)
            var stories: [Story] = []
            var persistedStories: [PersistedStory] = []

            for _ in 0..<storyCount {
                let useVideo = Bool.random() && !shuffledVideos.isEmpty

                if useVideo {
                    // Rotate through shuffled video pool
                    let video = shuffledVideos[videoIdx % shuffledVideos.count]
                    videoIdx += 1

                    if let videoFile = PexelsService.selectVideoFile(from: video.videoFiles),
                       let mediaURL = URL(string: videoFile.link) {
                        let mediaId = String(video.id)
                        let compositeId = Story.compositeId(userId: userId, mediaId: mediaId, blockIndex: index)
                        let duration = min(TimeInterval(video.duration), Constants.maxVideoDuration)
                        let postedAt = Date().addingTimeInterval(-Double.random(in: 3600...86400))

                        stories.append(Story(
                            id: compositeId,
                            pexelsMediaId: mediaId,
                            mediaURL: mediaURL,
                            type: .video,
                            duration: duration,
                            postedAt: postedAt
                        ))
                        persistedStories.append(PersistedStory(
                            pexelsMediaId: mediaId,
                            mediaURL: videoFile.link,
                            mediaType: "video",
                            duration: duration,
                            postedAt: postedAt
                        ))
                    }
                } else if !shuffledPhotos.isEmpty {
                    // Rotate through shuffled photo pool
                    let photo = shuffledPhotos[photoIdx % shuffledPhotos.count]
                    photoIdx += 1

                    if let mediaURL = URL(string: photo.src.portrait) {
                        let mediaId = String(photo.id)
                        let compositeId = Story.compositeId(userId: userId, mediaId: mediaId, blockIndex: index)
                        let postedAt = Date().addingTimeInterval(-Double.random(in: 3600...86400))

                        stories.append(Story(
                            id: compositeId,
                            pexelsMediaId: mediaId,
                            mediaURL: mediaURL,
                            type: .photo,
                            duration: Constants.photoAutoAdvanceDuration,
                            postedAt: postedAt
                        ))
                        persistedStories.append(PersistedStory(
                            pexelsMediaId: mediaId,
                            mediaURL: photo.src.portrait,
                            mediaType: "photo",
                            duration: Constants.photoAutoAdvanceDuration,
                            postedAt: postedAt
                        ))
                    }
                }
            }

            guard !stories.isEmpty else { continue }

            let user = User(id: userId, displayName: userId, avatarURL: avatarURL, stories: stories)
            newUsers.append(user)

            let persisted = PersistedUser(
                id: userId,
                displayName: userId,
                blockIndex: index,
                avatarURL: avatarURLString,
                stories: persistedStories
            )
            persistedUsers.append(persisted)
        }

        persistenceService.saveUsers(persistedUsers)
        users.append(contentsOf: newUsers)
        currentBlockIndex = index
    }

    // MARK: - Domain Conversion

    private func toDomainUser(_ persisted: PersistedUser) -> User {
        let stories = persisted.stories.compactMap { ps -> Story? in
            guard let url = URL(string: ps.mediaURL) else { return nil }
            let type: MediaType = ps.mediaType == "video" ? .video : .photo
            let compositeId = Story.compositeId(
                userId: persisted.id,
                mediaId: ps.pexelsMediaId,
                blockIndex: persisted.blockIndex
            )
            return Story(
                id: compositeId,
                pexelsMediaId: ps.pexelsMediaId,
                mediaURL: url,
                type: type,
                duration: ps.duration,
                postedAt: ps.postedAt
            )
        }
        return User(
            id: persisted.id,
            displayName: persisted.displayName,
            avatarURL: URL(string: persisted.avatarURL) ?? URL(string: "https://via.placeholder.com/100")!,
            stories: stories
        )
    }
}
