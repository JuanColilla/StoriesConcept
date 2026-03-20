import ComposableArchitecture
import Foundation
import os
import Sharing

@Reducer
struct StoryListFeature {
    struct ContentPayload: Equatable, Sendable {
        let photos: [PexelsPhoto]
        let videos: [PexelsVideo]
        let avatars: [PexelsPhoto]
    }

    struct MoreContentPayload: Equatable, Sendable {
        let photos: [PexelsPhoto]
        let videos: [PexelsVideo]
    }
    @ObservableState
    struct State: Equatable {
        var users: [User] = []
        var isLoading = false
        var errorMessage: String?
        var currentBlockIndex = -1

        // Content pools for user generation
        var photoPool: [PexelsPhoto] = []
        var videoPool: [PexelsVideo] = []
        var avatarPool: [PexelsPhoto] = []

        // Track all generated user IDs to prevent duplicates across blocks
        var generatedUserIds: Set<String> = []

        // Navigation — modal player
        @Presents var player: StoryPlayerFeature.State?
    }

    enum Action {
        // User interactions
        case onAppear
        case refresh
        case retry
        case userTapped(index: Int)
        case loadMoreIfNeeded(currentIndex: Int)
        case prefetchThumbnails(visibleUsers: [User])

        // Effect responses
        case initialLoadResponse(Result<ContentPayload, Error>)
        case blockGenerated(users: [User], persisted: [PersistedUser], blockIndex: Int)
        case moreContentLoaded(Result<MoreContentPayload, Error>)
        case refreshCompleted(Result<ContentPayload, Error>)
        case seenCacheLoaded(Set<String>)
        case likedCacheLoaded(Set<String>)
        case persistedUsersLoaded([PersistedUser])

        // Child reducer
        case player(PresentationAction<StoryPlayerFeature.Action>)
    }

    @Dependency(\.pexelsClient) var pexelsClient
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.prefetchClient) var prefetchClient
    @Dependency(\.networkClient) var networkClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // MARK: - Lifecycle

            case .onAppear:
                guard state.users.isEmpty else { return .none }
                state.isLoading = true
                return .merge(
                    loadPersistedUsers(),
                    bootstrapCaches()
                )

            case .persistedUsersLoaded(let persisted):
                if !persisted.isEmpty {
                    // Keep only the last 3 blocks to prevent unbounded growth
                    let maxBlock = persisted.map(\.blockIndex).max() ?? 0
                    let minBlock = max(0, maxBlock - 2)
                    let recent = persisted.filter { $0.blockIndex >= minBlock }
                    state.users = recent.map { UserGenerator.toDomainUser($0) }
                    state.generatedUserIds = Set(recent.map(\.id))
                    state.currentBlockIndex = maxBlock
                    state.isLoading = false
                    Logger.list.info("Loaded \(recent.count, privacy: .public) of \(persisted.count, privacy: .public) persisted users (blocks \(minBlock, privacy: .public)-\(maxBlock, privacy: .public))")
                    // Clean up old blocks in background
                    if recent.count < persisted.count {
                        return .run { _ in
                            try? await persistenceClient.deleteAllUsers()
                            nonisolated(unsafe) let toSave = recent
                            try? await persistenceClient.saveUsers(toSave)
                        }
                    }
                    return .none
                }
                // No persisted users — fetch from API
                return loadInitialContent()

            case .initialLoadResponse(.success(let payload)):
                state.isLoading = false
                state.photoPool = payload.photos
                state.videoPool = payload.videos
                state.avatarPool = payload.avatars
                let result = UserGenerator.generate(
                    blockIndex: 0,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool,
                    existingUserIds: state.generatedUserIds
                )
                state.users = result.users
                state.generatedUserIds.formUnion(result.users.map(\.id))
                state.currentBlockIndex = 0
                Logger.list.info("Generated block 0: \(result.users.count, privacy: .public) users")
                return .run { _ in
                    try await persistenceClient.saveUsers(result.persisted)
                }

            case .initialLoadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                Logger.list.error("Initial load failed: \(error, privacy: .public)")
                return .none

            // MARK: - Pagination

            case .loadMoreIfNeeded(let currentIndex):
                guard currentIndex >= state.users.count - 3,
                      !state.isLoading else { return .none }

                let nextBlock = state.currentBlockIndex + 1

                if nextBlock <= 1 {
                    state.isLoading = true
                    return .run { send in
                        Logger.list.info("Fetching block \(nextBlock, privacy: .public)")
                        let photos = try await pexelsClient.fetchCuratedPhotos(nextBlock + 1, 40)
                        let videos = try await pexelsClient.fetchPopularVideos(nextBlock + 1, 20)
                        await send(.moreContentLoaded(.success(
                            MoreContentPayload(photos: photos, videos: videos)
                        )))
                    } catch: { error, send in
                        await send(.moreContentLoaded(.failure(error)))
                    }
                } else {
                    // Block 2+: recycle from existing pools
                    if state.photoPool.isEmpty && state.videoPool.isEmpty {
                        // Pools empty (app restarted from persistence) — refetch
                        state.isLoading = true
                        return loadInitialContent()
                    }
                    let photos = state.photoPool
                    let videos = state.videoPool
                    let avatars = state.avatarPool
                    let existingIds = state.generatedUserIds
                    return .run { send in
                        let result = UserGenerator.generate(
                            blockIndex: nextBlock,
                            photos: photos, videos: videos, avatars: avatars,
                            existingUserIds: existingIds
                        )
                        await send(.blockGenerated(
                            users: result.users,
                            persisted: result.persisted,
                            blockIndex: nextBlock
                        ))
                    }
                }

            case .moreContentLoaded(.success(let payload)):
                state.isLoading = false
                state.photoPool.append(contentsOf: payload.photos)
                state.videoPool.append(contentsOf: payload.videos)
                let nextBlock = state.currentBlockIndex + 1
                let result = UserGenerator.generate(
                    blockIndex: nextBlock,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool,
                    existingUserIds: state.generatedUserIds
                )
                state.users.append(contentsOf: result.users)
                state.generatedUserIds.formUnion(result.users.map(\.id))
                state.currentBlockIndex = nextBlock
                let blockIndex = state.currentBlockIndex
                return .run { _ in
                    try await persistenceClient.saveUsers(result.persisted)
                    Logger.list.info("Block \(blockIndex, privacy: .public) generated")
                }

            case .moreContentLoaded(.failure(let error)):
                state.isLoading = false
                Logger.list.error("More content failed: \(error, privacy: .public)")
                return .none

            case .blockGenerated(let users, let persisted, let blockIndex):
                state.users.append(contentsOf: users)
                state.generatedUserIds.formUnion(users.map(\.id))
                state.currentBlockIndex = blockIndex
                nonisolated(unsafe) let toSave = persisted
                return .run { _ in
                    try await persistenceClient.saveUsers(toSave)
                }

            // MARK: - Refresh

            case .refresh:
                guard networkClient.isConnected() else { return .none }
                state.isLoading = true
                return .run { send in
                    Logger.list.info("Pull-to-refresh")
                    let photos = try await pexelsClient.fetchCuratedPhotos(Int.random(in: 1...2), 40)
                    let videos = try await pexelsClient.fetchPopularVideos(Int.random(in: 1...2), 20)
                    let avatars = try await pexelsClient.fetchAvatarPhotos(1, 50)
                    await send(.refreshCompleted(.success(
                        ContentPayload(photos: photos, videos: videos, avatars: avatars)
                    )))
                } catch: { error, send in
                    await send(.refreshCompleted(.failure(error)))
                }

            case .refreshCompleted(.success(let payload)):
                state.isLoading = false
                state.photoPool = payload.photos
                state.videoPool = payload.videos
                state.avatarPool = payload.avatars
                let nextBlock = state.currentBlockIndex + 1
                let result = UserGenerator.generate(
                    blockIndex: nextBlock,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool,
                    existingUserIds: state.generatedUserIds
                )
                // Prepend new users at top
                state.users.insert(contentsOf: result.users, at: 0)
                state.generatedUserIds.formUnion(result.users.map(\.id))
                state.currentBlockIndex = nextBlock
                return .run { _ in
                    try await persistenceClient.saveUsers(result.persisted)
                }

            case .refreshCompleted(.failure):
                state.isLoading = false
                return .none

            case .retry:
                state.errorMessage = nil
                state.users = []
                return .send(.onAppear)

            // MARK: - Navigation

            case .userTapped(let index):
                let user = state.users[index]
                let storyIds = user.stories.map(\.id)
                @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
                let firstUnseen = Self.firstUnseen(storyIds: storyIds, seenIds: seenIds)
                state.player = StoryPlayerFeature.State(
                    allUsers: state.users,
                    currentUserIndex: index,
                    currentStoryIndex: firstUnseen
                )
                return .none

            // MARK: - Player delegate

            case .player(.presented(.delegate(.storySeen(let id)))):
                Logger.list.info("Story seen: \(id, privacy: .public)")
                return .none

            case .player:
                return .none

            // MARK: - Caches

            case .seenCacheLoaded(let ids):
                @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
                $seenIds.withLock { $0 = ids }
                return .none

            case .likedCacheLoaded(let ids):
                @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []
                $likedIds.withLock { $0 = ids }
                return .none

            // MARK: - Prefetch

            case .prefetchThumbnails(let users):
                return .run { _ in
                    await prefetchClient.prefetchThumbnails(users)
                }
            }
        }
        .ifLet(\.$player, action: \.player) {
            StoryPlayerFeature()
        }
    }

    // MARK: - Effect Helpers

    private func loadPersistedUsers() -> Effect<Action> {
        .run { send in
            let persisted = try await persistenceClient.fetchAllUsers()
            await send(.persistedUsersLoaded(persisted))
        }
    }

    private func loadInitialContent() -> Effect<Action> {
        .run { send in
            Logger.list.info("Fetching initial content from API")
            async let photos = pexelsClient.fetchCuratedPhotos(1, 40)
            async let videos = pexelsClient.fetchPopularVideos(1, 20)
            async let avatars = pexelsClient.fetchAvatarPhotos(1, 50)
            let (p, v, a) = try await (photos, videos, avatars)
            await send(.initialLoadResponse(.success(
                ContentPayload(photos: p, videos: v, avatars: a)
            )))
        } catch: { error, send in
            await send(.initialLoadResponse(.failure(error)))
        }
    }

    private func bootstrapCaches() -> Effect<Action> {
        .run { send in
            let seen = try await persistenceClient.loadSeenCache()
            await send(.seenCacheLoaded(seen))
            let liked = try await persistenceClient.loadLikedCache()
            await send(.likedCacheLoaded(liked))
        }
    }

    static func firstUnseen(storyIds: [String], seenIds: Set<String>) -> Int {
        for (index, id) in storyIds.enumerated() {
            if !seenIds.contains(id) { return index }
        }
        return 0
    }
}
