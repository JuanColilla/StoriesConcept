# StoriesConcept — TCA Migration Design Spec

> **Date:** 2026-03-20
> **Status:** Reviewed
> **Scope:** Full migration from MVVM/@Observable to TCA (The Composable Architecture)
> **Goal:** Demonstrate professional TCA mastery for technical test evaluation + deep learning

---

## 1. Executive Summary

Migrate StoriesConcept from MVVM with `@Observable` to The Composable Architecture (TCA v1.25.1), using:
- **TCA** for state management, effects, and composition
- **swift-sharing** (`@Shared(.inMemory)`) for cross-feature session caches
- **swift-snapshot-testing** for visual regression testing
- **SwiftData** retained as persistence layer (no replacement)
- **os.Logger** structured logging throughout
- **Dual observation:** `@ObservableState` (TCA) + `@Observable` (Apple) where each fits

**Approach:** Bottom-Up migration — Dependencies → Reducers → Views. Each step compilable and testeable.

**Prerequisites:** Domain models (`User`, `Story`, `MediaType`) and DTOs (`PexelsPhoto`, `PexelsVideo`, `PexelsVideoFile`, `PexelsSrc`) must conform to `Equatable` (required by TCA's `@ObservableState` and `TestStore`). Most already have `Codable` + `Sendable`; add `Equatable` where missing.

**Testing framework split:** Unit and integration tests use Swift Testing (`@Test`, `@Suite`). Snapshot tests use XCTest (required by `swift-snapshot-testing`).

---

## 2. Architecture Overview

```
AppFeature (composition root)
  └── Scope → StoryListFeature
                ├── @Presents → StoryPlayerFeature
                └── Dependencies:
                      ├── PexelsClient
                      ├── CacheClient
                      ├── PrefetchClient
                      ├── PersistenceClient
                      ├── HapticClient
                      ├── NetworkClient (@Observable)
                      └── ContinuousClock (TCA built-in)

@Shared(.inMemory):
  ├── "seenIds"  → Set<String>  (cross-feature session cache)
  └── "likedIds" → Set<String>  (cross-feature session cache)

Persistence (SwiftData — retained):
  ├── PersistedUser → source of truth for generated users
  └── StoryState    → source of truth for seen/liked states
```

### Layers (migration mapping)

```
BEFORE (MVVM)                          AFTER (TCA)
─────────────────                      ─────────────────
Views (@State vm)           →          Views (@Bindable store)
ViewModels (@Observable)    →          Reducers (@ObservableState)
Services (@Observable)      →          Dependencies (DependencyKey)
Models (Domain/DTO/Persist) →          Models (unchanged)
```

---

## 3. Observation Strategy (Dual System)

### Why dual observation matters

The interviewers value `@Observable` (iOS 17 Observation framework) highly. TCA uses its own `@ObservableState` macro. Demonstrating correct usage of BOTH shows architectural maturity.

### Where each system applies

| Context | Observation System | Rationale |
|---------|-------------------|-----------|
| Reducer State | `@ObservableState` | TCA controls mutations, enables exhaustive testing, granular observation |
| NetworkClient (live) | `@Observable` | Apple's native observation for a reactive system monitor — not TCA-managed |
| `@Shared` in `@Observable` models | `@ObservationIgnored` + `@Shared` | Avoids macro conflict — `@Shared` manages its own observation |
| Views consuming Store | `@Bindable var store` | TCA's bridge to SwiftUI observation |

### Technical explanation

**`@ObservableState`** is TCA's macro that makes `State` structs participate in SwiftUI's observation system. Unlike `@Observable` (which works on classes), `@ObservableState` works on structs and integrates with TCA's controlled mutation model — state only changes inside a reducer, never directly.

**`@Observable`** (Apple) is used for objects that live outside TCA's reducer lifecycle. The `NetworkMonitorClient` is a good example: it wraps `NWPathMonitor`, publishes `isConnected`, and SwiftUI views can observe it directly. It doesn't need TCA's action/state/effect discipline because it's a read-only reactive value.

**The bridge (`@ObservationIgnored`):** When `@Shared` properties live inside an `@Observable` class, the `@Observable` macro tries to generate observation tracking that conflicts with `@Shared`'s own tracking. Adding `@ObservationIgnored` tells `@Observable` to ignore that property — `@Shared` handles observation itself.

---

## 4. Dependencies Layer

### What are TCA Dependencies?

In MVVM, services are classes injected via initializers or singletons. In TCA, dependencies are **value types with closures** registered in a global dependency graph. This enables:

1. **`liveValue`** — real implementation (production)
2. **`testValue`** — `unimplemented()` closures that fail explicitly if called without override
3. **`previewValue`** — mock data for SwiftUI previews

The key insight: tests MUST declare every dependency they use. If a test accidentally triggers an API call, `unimplemented()` crashes immediately — no silent bugs.

### Client definitions

#### PexelsClient

```swift
@DependencyClient
struct PexelsClient {
    var fetchCuratedPhotos: @Sendable (_ page: Int) async throws -> [PexelsPhoto]
    var fetchPopularVideos: @Sendable (_ page: Int) async throws -> [PexelsVideo]
    var fetchAvatarPhotos: @Sendable () async throws -> [PexelsPhoto]
    var downloadData: @Sendable (_ url: URL) async throws -> Data
}

extension PexelsClient: DependencyKey {
    static let liveValue = PexelsClient(
        fetchCuratedPhotos: { page in /* URLSession to Pexels API */ },
        fetchPopularVideos: { page in /* URLSession to Pexels API */ },
        fetchAvatarPhotos: { /* URLSession to Pexels API */ },
        downloadData: { url in /* URLSession download */ }
    )
    // testValue auto-generated by @DependencyClient → all unimplemented()
    static let previewValue = PexelsClient(
        fetchCuratedPhotos: { _ in PexelsPhoto.mocks },
        fetchPopularVideos: { _ in PexelsVideo.mocks },
        fetchAvatarPhotos: { PexelsPhoto.avatarMocks },
        downloadData: { _ in Data() }
    )
}

extension DependencyValues {
    var pexelsClient: PexelsClient {
        get { self[PexelsClient.self] }
        set { self[PexelsClient.self] = newValue }
    }
}
```

#### CacheClient

```swift
@DependencyClient
struct CacheClient {
    var save: @Sendable (_ data: Data, _ mediaId: String, _ ttl: TimeInterval) async -> Void
    var load: @Sendable (_ mediaId: String) async -> Data?
    var isAvailable: @Sendable (_ mediaId: String) -> Bool
    var clearAll: @Sendable () async -> Void
}
```

#### PersistenceClient

```swift
@DependencyClient
struct PersistenceClient {
    // Users
    var saveUsers: @Sendable (_ users: [User], _ blockIndex: Int) async throws -> Void
    var fetchUsers: @Sendable (_ blockIndex: Int?) async throws -> [User]
    var maxBlockIndex: @Sendable () async -> Int
    // Story states
    var markSeen: @Sendable (_ storyId: String) async throws -> Void
    var setLiked: @Sendable (_ storyId: String, _ liked: Bool) async throws -> Void
    var isSeen: @Sendable (_ storyId: String) -> Bool
    var isLiked: @Sendable (_ storyId: String) -> Bool
    var unseenCount: @Sendable (_ user: User) -> Int
    var allSeen: @Sendable (_ user: User) -> Bool
    var firstUnseenIndex: @Sendable (_ user: User) -> Int
    // Cache bootstrap
    var loadSeenCache: @Sendable () async throws -> Set<String>
    var loadLikedCache: @Sendable () async throws -> Set<String>
}
```

#### PrefetchClient

```swift
@DependencyClient
struct PrefetchClient {
    var prefetchThumbnails: @Sendable (_ users: [User]) async -> Void
    var prefetchStories: @Sendable (_ currentUser: User, _ nextUser: User?) async -> Void
    var cancelAll: @Sendable () -> Void
}
```

#### HapticClient

```swift
@DependencyClient
struct HapticClient {
    var storyChanged: @Sendable () -> Void
    var userChanged: @Sendable () -> Void
    var liked: @Sendable () -> Void
}
```

#### NetworkClient — special case

```swift
// Uses @Observable because it exposes a reactive property, not just actions
@Observable
final class NetworkMonitorLive {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    func stop() { monitor.cancel() }
}

// NetworkClient bridges @Observable (reactive) with TCA (dependency injection)
// The live implementation holds the @Observable instance for direct SwiftUI observation.
// The reducer uses observeConnectivity stream for effect-based reactivity.
@DependencyClient
struct NetworkClient {
    var start: @Sendable () -> Void
    var stop: @Sendable () -> Void
    var isConnected: @Sendable () -> Bool
    var observeConnectivity: @Sendable () -> AsyncStream<Bool> = { .finished }
}

// Registration — live value holds the @Observable instance
extension NetworkClient: DependencyKey {
    static let liveValue: NetworkClient = {
        let monitor = NetworkMonitorLive()
        return NetworkClient(
            start: { monitor.start() },
            stop: { monitor.stop() },
            isConnected: { monitor.isConnected },
            observeConnectivity: {
                AsyncStream { continuation in
                    // Observe @Observable changes via withObservationTracking
                    // or use NWPathMonitor callbacks directly
                    let pathMonitor = NWPathMonitor()
                    pathMonitor.pathUpdateHandler = { path in
                        continuation.yield(path.status == .satisfied)
                    }
                    pathMonitor.start(queue: DispatchQueue(label: "NetworkStream"))
                    continuation.onTermination = { _ in pathMonitor.cancel() }
                }
            }
        )
    }()
}

// Views that need reactive observation can access the @Observable instance
// via the live environment. Reducer uses the AsyncStream for effect-based observation.
```

### How dependencies are used in reducers

```swift
@Reducer
struct StoryListFeature {
    @Dependency(\.pexelsClient) var pexelsClient
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.prefetchClient) var prefetchClient
    @Dependency(\.continuousClock) var clock
    // ... used inside Effects
}
```

### Technical note: `@DependencyClient` macro

The `@DependencyClient` macro (TCA) auto-generates `testValue` with `unimplemented()` for every closure. This means:
- You only write `liveValue` and `previewValue`
- Tests that forget to override a dependency **fail immediately** with a clear message
- No silent network calls or disk writes in tests

---

## 5. StoryPlayerFeature Reducer

### State

```swift
@Reducer
struct StoryPlayerFeature {
    @ObservableState
    struct State: Equatable {
        var allUsers: [User]
        var currentUserIndex: Int
        var currentStoryIndex: Int

        // Timer & playback
        var progress: Double = 0
        var isTimerRunning = false
        var isPaused = false
        var isContentLoading = false

        // Interaction
        var isLiked = false
        var shouldDismiss = false

        // Computed
        var currentUser: User { allUsers[currentUserIndex] }
        var currentStory: Story { currentUser.stories[currentStoryIndex] }
        var totalStories: Int { currentUser.stories.count }
    }
```

### Actions

```swift
    // Note: Action does NOT need Equatable in TCA v1.25.1.
    // TestStore uses CaseKeyPath-based receive(\.actionKeyPath) syntax.
    enum Action {
        // User interactions
        case tappedRight
        case tappedLeft
        case swipedToNextUser
        case swipedToPreviousUser
        case swipedDown
        case toggleLike
        case longPressStarted
        case longPressEnded

        // Timer system
        case timerTick(Double)
        case storyCompleted

        // Content loading
        case contentLoaded(Story.ID)
        case contentCheckTick

        // Lifecycle
        case onAppear
        case onDisappear
        case appBackgrounded
        case appForegrounded

        // Delegate — communication to parent
        case delegate(Delegate)

        enum Delegate {
            case storySeen(Story.ID)
            case dismissed
        }
    }
```

### Cancel IDs

```swift
    enum CancelID {
        case timer
        case contentCheck
        case prefetch
    }
```

### Reducer body

```swift
    @Dependency(\.continuousClock) var clock
    @Dependency(\.cacheClient) var cacheClient
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.prefetchClient) var prefetchClient
    @Dependency(\.hapticClient) var hapticClient

    @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
    @Shared(.inMemory("likedIds")) var likedIds: Set<String> = []

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // MARK: - Navigation
            case .tappedRight:
                return advanceStory(&state)

            case .tappedLeft:
                return retreatStory(&state)

            case .swipedToNextUser:
                return advanceUser(&state)

            case .swipedToPreviousUser:
                return retreatUser(&state)

            case .swipedDown:
                return dismiss(&state)

            // MARK: - Timer
            case .onAppear:
                // startPlayback checks cache availability, sets loading flags, starts timer
                return startPlayback(&state)
                // Implementation: sets isTimerRunning = true, checks isContentAvailable,
                // if content cached → startTimer(), if not → isContentLoading = true + poll

            case .timerTick(let elapsed):
                let duration = storyDuration(state.currentStory)
                state.progress = min(elapsed / duration, 1.0)
                return .none

            case .storyCompleted:
                return .merge(
                    markSeenEffect(state),
                    advanceStory(&state)
                )

            // MARK: - Interactions
            case .toggleLike:
                state.isLiked.toggle()
                let id = state.currentStory.id
                let liked = state.isLiked
                $likedIds.withLock { liked ? $0.insert(id) : $0.remove(id) }
                return .run { _ in
                    hapticClient.liked()
                    try await persistenceClient.setLiked(id, liked)
                }

            case .longPressStarted:
                state.isPaused = true
                return .cancel(id: CancelID.timer)

            case .longPressEnded:
                state.isPaused = false
                return startTimer(&state)

            // MARK: - Lifecycle
            case .appBackgrounded:
                state.isPaused = true
                return .cancel(id: CancelID.timer)

            case .appForegrounded:
                state.isPaused = false
                return startTimer(&state)

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.timer),
                    .cancel(id: CancelID.contentCheck),
                    .cancel(id: CancelID.prefetch)
                )

            // MARK: - Content loading
            case .contentLoaded:
                state.isContentLoading = false
                return startTimer(&state)

            case .contentCheckTick:
                if cacheClient.isAvailable(state.currentStory.mediaId) {
                    state.isContentLoading = false
                    return .merge(
                        .cancel(id: CancelID.contentCheck),
                        startTimer(&state)
                    )
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }
```

### Timer implementation with ContinuousClock

```swift
    private func startTimer(_ state: inout State) -> Effect<Action> {
        let story = state.currentStory
        let duration = storyDuration(story)
        let startProgress = state.progress

        return .run { send in
            let startOffset = startProgress * duration
            let start = clock.now

            for await _ in clock.timer(interval: .milliseconds(16)) {
                let elapsed = clock.now - start
                // Duration doesn't have .asSeconds — compute manually
                let elapsedSeconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
                let total = startOffset + elapsedSeconds
                if total >= duration {
                    await send(.storyCompleted)
                    return
                }
                await send(.timerTick(total))
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func storyDuration(_ story: Story) -> Double {
        switch story.type {
        case .photo: return Constants.photoDisplayDuration  // 15s
        case .video: return min(story.duration, Constants.maxVideoDuration)  // capped 45s
        }
    }
```

### Key helper: markSeenEffect

```swift
    private func markSeenEffect(_ state: State) -> Effect<Action> {
        let storyId = state.currentStory.id
        // 1. Update @Shared cache (immediate, cross-feature)
        $seenIds.withLock { $0.insert(storyId) }
        // 2. Persist to SwiftData (async, durable)
        // 3. Emit delegate to notify parent
        return .merge(
            .run { _ in
                try await persistenceClient.markSeen(storyId)
                Logger.player.info("Persisted seen: \(storyId, privacy: .public)")
            },
            .send(.delegate(.storySeen(storyId)))
        )
    }
```

**Testing @Shared mutations:** Since `@Shared` lives on the reducer (not in State), tests verify seen behavior through:
1. Effect-based verification: assert `persistenceClient.markSeen` was called with correct ID
2. Delegate verification: `store.receive(\.delegate.storySeen)` confirms the action was emitted
3. Direct `@Shared` inspection in tests: `@Shared(.inMemory("seenIds"))` can be read in test scope

### Technical explanation: Effects and Cancellation

**Effects** are TCA's way of handling side effects (network, disk, timers). An Effect is a value that describes async work — it doesn't execute until TCA schedules it.

**`.cancellable(id:)`** tags an effect with an ID. When you return `.cancel(id:)`, TCA cancels any running effect with that ID. This is how:
- Long press pauses the timer: `.cancel(id: .timer)`
- Resume restarts it: `startTimer()` returns a new `.cancellable(id: .timer)`
- `cancelInFlight: true` means starting a new timer auto-cancels the previous one

**`.merge()`** runs multiple effects concurrently. Used when story completion needs to both persist the seen state AND advance to the next story.

### Delegate pattern explained

When the player marks a story as seen, the parent (list) needs to know — but the player shouldn't know about the list. The solution:

1. Player emits `.delegate(.storySeen(id))` — a pure data signal
2. Player's reducer returns `.none` for delegate actions (it doesn't handle them)
3. Parent's `.ifLet` composition routes delegate actions to the parent reducer
4. Parent handles them: update badges, persist, etc.

This keeps features decoupled. The player works identically whether composed in a list, a test, or a preview.

---

## 6. StoryListFeature Reducer

### State

```swift
@Reducer
struct StoryListFeature {
    @ObservableState
    struct State: Equatable {
        var users: [User] = []
        var isLoading = false
        var errorMessage: String?
        var currentBlockIndex = 0

        // Content pools for user generation
        var photoPool: [PexelsPhoto] = []
        var videoPool: [PexelsVideo] = []
        var avatarPool: [PexelsPhoto] = []

        // Navigation — modal player
        @Presents var player: StoryPlayerFeature.State?
    }
```

### Actions

```swift
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
        case blockGenerated([User])
        case moreContentLoaded(Result<ContentPayload, Error>)
        case refreshCompleted(Result<ContentPayload, Error>)
        case seenCacheLoaded(Set<String>)
        case likedCacheLoaded(Set<String>)

        // Child reducer
        case player(PresentationAction<StoryPlayerFeature.Action>)
    }
```

### Supporting types

```swift
    struct ContentPayload: Equatable {
        let photos: [PexelsPhoto]
        let videos: [PexelsVideo]
        let avatars: [PexelsPhoto]?  // only on initial load
    }
```

### Reducer body

```swift
    @Dependency(\.pexelsClient) var pexelsClient
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.prefetchClient) var prefetchClient
    @Dependency(\.networkClient) var networkClient

    @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []
    // Note: likedIds NOT declared here — list doesn't display like state

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                guard state.users.isEmpty else { return .none }
                state.isLoading = true
                return .merge(
                    loadInitialContent(),
                    bootstrapCaches()
                )

            case .initialLoadResponse(.success(let payload)):
                state.isLoading = false
                state.photoPool = payload.photos
                state.videoPool = payload.videos
                if let avatars = payload.avatars {
                    state.avatarPool = avatars
                }
                let users = UserGenerator.generate(
                    blockIndex: 0,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool
                )
                state.users = users
                state.currentBlockIndex = 0
                return .run { _ in
                    try await persistenceClient.saveUsers(users, 0)
                }

            case .initialLoadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                Logger.list.error("Initial load failed: \(error, privacy: .public)")
                return .none

            case .userTapped(let index):
                let user = state.users[index]
                let firstUnseen = persistenceClient.firstUnseenIndex(user)
                state.player = StoryPlayerFeature.State(
                    allUsers: state.users,
                    currentUserIndex: index,
                    currentStoryIndex: firstUnseen
                )
                return .none

            case .loadMoreIfNeeded(let currentIndex):
                guard currentIndex >= state.users.count - 3,
                      !state.isLoading else { return .none }

                let nextBlock = state.currentBlockIndex + 1

                if nextBlock <= 1 {
                    state.isLoading = true
                    return .run { send in
                        Logger.list.info("Fetching block \(nextBlock, privacy: .public)")
                        let photos = try await pexelsClient.fetchCuratedPhotos(nextBlock + 1)
                        let videos = try await pexelsClient.fetchPopularVideos(nextBlock + 1)
                        await send(.moreContentLoaded(.success(
                            ContentPayload(photos: photos, videos: videos, avatars: nil)
                        )))
                    } catch: { error, send in
                        await send(.moreContentLoaded(.failure(error)))
                    }
                } else {
                    return .run { [photos = state.photoPool, videos = state.videoPool,
                                   avatars = state.avatarPool] send in
                        let users = UserGenerator.generate(
                            blockIndex: nextBlock, photos: photos,
                            videos: videos, avatars: avatars
                        )
                        await send(.blockGenerated(users))
                    }
                }

            case .blockGenerated(let newUsers):
                state.users.append(contentsOf: newUsers)
                state.currentBlockIndex += 1
                // Capture value BEFORE .run — inout state cannot be captured in @Sendable closure
                let blockIndex = state.currentBlockIndex
                return .run { _ in
                    try await persistenceClient.saveUsers(newUsers, blockIndex)
                }

            // MARK: - Player delegate
            case .player(.presented(.delegate(.storySeen(let id)))):
                Logger.list.info("Story seen: \(id, privacy: .public)")
                return .none  // @Shared seenIds already updated by player

            case .player(.presented(.delegate(.dismissed))):
                state.player = nil
                return .none

            case .player:
                return .none

            // MARK: - Caches
            case .seenCacheLoaded(let ids):
                $seenIds.withLock { $0 = ids }
                return .none

            case .likedCacheLoaded(let ids):
                $likedIds.withLock { $0 = ids }
                return .none

            case .refresh:
                // Pull-to-refresh: fetch fresh content for block 0, replace existing users
                state.isLoading = true
                return .run { send in
                    Logger.list.info("Pull-to-refresh triggered")
                    let photos = try await pexelsClient.fetchCuratedPhotos(1)
                    let videos = try await pexelsClient.fetchPopularVideos(1)
                    await send(.refreshCompleted(.success(
                        ContentPayload(photos: photos, videos: videos, avatars: nil)
                    )))
                } catch: { error, send in
                    Logger.list.error("Refresh failed: \(error, privacy: .public)")
                    await send(.refreshCompleted(.failure(error)))
                }

            case .refreshCompleted(.success(let payload)):
                state.isLoading = false
                state.photoPool = payload.photos
                state.videoPool = payload.videos
                let freshUsers = UserGenerator.generate(
                    blockIndex: 0,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool
                )
                state.users = freshUsers
                state.currentBlockIndex = 0
                return .run { _ in
                    try await persistenceClient.saveUsers(freshUsers, 0)
                }

            case .refreshCompleted(.failure):
                state.isLoading = false
                // Silently fail — existing data remains visible
                return .none

            case .moreContentLoaded(.success(let payload)):
                state.isLoading = false
                state.photoPool.append(contentsOf: payload.photos)
                state.videoPool.append(contentsOf: payload.videos)
                let nextBlock = state.currentBlockIndex + 1
                let newUsers = UserGenerator.generate(
                    blockIndex: nextBlock,
                    photos: state.photoPool,
                    videos: state.videoPool,
                    avatars: state.avatarPool
                )
                state.users.append(contentsOf: newUsers)
                state.currentBlockIndex = nextBlock
                let blockIndex = state.currentBlockIndex
                return .run { _ in
                    try await persistenceClient.saveUsers(newUsers, blockIndex)
                }

            case .moreContentLoaded(.failure(let error)):
                state.isLoading = false
                Logger.list.error("More content failed: \(error, privacy: .public)")
                return .none

            case .retry:
                state.errorMessage = nil
                return .send(.onAppear)

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
```

### Technical explanation: `@Presents` + `.ifLet`

**`@Presents`** is a property wrapper that marks optional child state as a presentation destination. When non-nil, the child feature is "presented" (modal, sheet, fullscreen cover, etc.).

**`.ifLet(\.$player, action: \.player) { StoryPlayerFeature() }`** does three things:
1. When `state.player != nil` — runs `StoryPlayerFeature` reducer for player actions
2. When `state.player` becomes `nil` — **automatically cancels ALL effects** from the player (timer, prefetch, content checks)
3. Routes delegate actions up to the parent

This means dismiss = `state.player = nil` → zero manual cleanup.

### Technical explanation: `PresentationAction`

`PresentationAction<StoryPlayerFeature.Action>` wraps child actions with presentation lifecycle:
- `.presented(childAction)` — the child emitted an action while presented
- `.dismiss` — the presentation was dismissed (system or programmatic)

---

## 7. AppFeature — Composition Root

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var storyList = StoryListFeature.State()
    }

    enum Action {
        case storyList(StoryListFeature.Action)
    }

    var body: some ReducerOf<Self> {
        // StoryListFeature handles its own .onAppear via the view's .task modifier.
        // AppFeature is the composition root — it scopes child reducers.
        // Additional app-level lifecycle (deep links, analytics) can be added here.
        Scope(state: \.storyList, action: \.storyList) {
            StoryListFeature()
        }
    }
}
```

### App entry point

```swift
@main
struct StoriesConceptApp: App {
    let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            StoryListView(
                store: store.scope(state: \.storyList, action: \.storyList)
            )
        }
    }
}
```

### Technical explanation: `Scope`

`Scope(state: \.storyList, action: \.storyList) { StoryListFeature() }` tells TCA: "run StoryListFeature, but only give it access to the `storyList` slice of the parent state, and route actions namespaced under `.storyList`." The child reducer never sees the parent's full state — isolation by construction.

---

## 8. @Shared — Cross-Feature Session Caches

### Purpose

`@Shared(.inMemory)` bridges the gap between SwiftData (source of truth) and real-time UI updates across features without coupling reducers via delegate actions for every read.

### What uses @Shared

| Key | Type | Written by | Read by | Backed by |
|-----|------|-----------|---------|-----------|
| `"seenIds"` | `Set<String>` | PlayerFeature | ListFeature (badges), PlayerFeature (progress bar) | SwiftData StoryState |
| `"likedIds"` | `Set<String>` | PlayerFeature | PlayerFeature (heart icon) | SwiftData StoryState |

> **Note:** `StoryListFeature` only declares `@Shared(.inMemory("seenIds"))` — it does NOT declare `likedIds` since the list never displays like state.

### Lifecycle

```
App launch
  → PersistenceClient.loadSeenCache() → SwiftData query → @Shared("seenIds")
  → PersistenceClient.loadLikedCache() → SwiftData query → @Shared("likedIds")

During session:
  → Player completes story → $seenIds.withLock { $0.insert(id) }
  → Concurrent: persistenceClient.markSeen(id) writes to SwiftData
  → List view observes @Shared → badge updates immediately

App restart:
  → @Shared(.inMemory) resets to empty
  → Bootstrap from SwiftData again
```

### What does NOT use @Shared

- Users array → Reducer state (local to ListFeature)
- Timer progress → Reducer state (ephemeral, local to PlayerFeature)
- Loading flags → Reducer state (local per feature)
- Generated content pools → Reducer state (local to ListFeature)

### Technical explanation: thread safety

`$seenIds.withLock { }` uses swift-sharing's built-in lock. Multiple features can read/write concurrently without data races. This is critical because TCA effects run on background threads, while SwiftUI reads on the main thread.

---

## 9. os.Logger Strategy

### Logger definitions

```swift
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let api      = Logger(subsystem: subsystem, category: "API")
    static let cache    = Logger(subsystem: subsystem, category: "Cache")
    static let player   = Logger(subsystem: subsystem, category: "Player")
    static let list     = Logger(subsystem: subsystem, category: "List")
    static let persist  = Logger(subsystem: subsystem, category: "Persistence")
    static let prefetch = Logger(subsystem: subsystem, category: "Prefetch")
    static let network  = Logger(subsystem: subsystem, category: "Network")
}
```

### Log levels

| Level | Usage | Example |
|-------|-------|---------|
| `.debug` | Internal flow, dev only | `"Timer tick: \(progress, privacy: .public)"` |
| `.info` | Business events | `"Story marked seen: \(storyId, privacy: .public)"` |
| `.error` | Recoverable failures | `"API fetch failed: \(error, privacy: .public)"` |
| `.fault` | Inconsistent state | `"User index out of bounds: \(index, privacy: .public)"` |

### Integration points

- **Effects:** All logging happens inside `.run { }` effects, not in state mutations
- **Dependencies:** Each client logs its own category (PexelsClient → Logger.api, CacheClient → Logger.cache)
- **Privacy:** `.public` for IDs, counts, types, states. Default (redacted) for URLs, user names

### Why os.Logger over print()

- Filterable by category in Console.app and Instruments
- Structured levels (debug/info/error/fault)
- Privacy-aware: redacted by default in release builds
- Zero performance cost when not being observed (lazy evaluation)
- Persisted in unified logging system for post-mortem analysis

---

## 10. Testing Plan

### Layer 1: Unit Tests — Exhaustive (`exhaustivity: .on`)

TestStore verifies every state mutation and every effect. If any action changes state without assertion, the test fails.

#### StoryPlayerFeatureTests (~15 tests)

| Test | What it verifies |
|------|-----------------|
| `testTimerStartsOnAppear` | onAppear → isTimerRunning = true, timer effect starts |
| `testTimerTickUpdatesProgress` | timerTick → progress updates proportionally |
| `testStoryCompletionMarksSeen` | storyCompleted → seen persisted, delegate emitted, advance to next |
| `testNextStoryWithinUser` | tappedRight → currentStoryIndex increments, progress resets |
| `testPreviousStoryWithinUser` | tappedLeft → currentStoryIndex decrements |
| `testNextUserAtLastStory` | tappedRight at last story → next user, storyIndex = 0 |
| `testSwipeToNextUser` | swipedToNextUser → currentUserIndex increments |
| `testSwipeToPreviousUser` | swipedToPreviousUser → currentUserIndex decrements |
| `testDismiss` | swipedDown → delegate.dismissed emitted |
| `testToggleLike` | toggleLike → isLiked toggles, persisted, haptic fired |
| `testLongPressPausesTimer` | longPressStarted → isPaused, timer cancelled |
| `testLongPressResumeTimer` | longPressEnded → !isPaused, timer restarted |
| `testAppBackgroundPauses` | appBackgrounded → isPaused, timer cancelled |
| `testAppForegroundResumes` | appForegrounded → !isPaused, timer restarted |
| `testContentLoadingWaitsForCache` | onAppear with uncached → isContentLoading, polling starts |

#### StoryListFeatureTests (~10 tests)

| Test | What it verifies |
|------|-----------------|
| `testInitialLoadSuccess` | onAppear → isLoading, API called, users populated |
| `testInitialLoadFailure` | API error → errorMessage set, isLoading false |
| `testRetryAfterError` | retry → errorMessage cleared, onAppear re-sent |
| `testPaginationBlock1` | loadMoreIfNeeded near end → API fetch, new users appended |
| `testPaginationBlock2Recycles` | block 2+ → no API call, users generated from pools |
| `testUserTapPresentsPlayer` | userTapped → player state non-nil with correct indices |
| `testPlayerDismissClearsState` | player delegate dismissed → player = nil |
| `testSeenDelegateFromPlayer` | player delegate storySeen → logged (cache updated via @Shared) |
| `testRefreshPullToRefresh` | refresh → fetch fresh content, prepend |
| `testPrefetchTriggeredOnScroll` | prefetchThumbnails → prefetchClient called |

### Layer 2: Integration Tests — Non-exhaustive (`exhaustivity: .off`)

Verify end-to-end flows without micro-asserting every intermediate state change.

#### StoryFlowIntegrationTests (~5 tests)

| Test | Flow |
|------|------|
| `testFullViewingFlow` | load → tap user → watch stories → dismiss → badges updated |
| `testPaginationFlow` | load → scroll → block 1 (API) → block 2 (recycle) |
| `testOfflineRetryFlow` | load fails → retry → succeeds |
| `testLikeAcrossFeatures` | tap user → like story → dismiss → like persisted |
| `testSeenStateSync` | player marks seen → @Shared updates → list reflects |

### Layer 3: Snapshot Tests — Visual regression

Using `swift-snapshot-testing` with `withSnapshotTesting(record: .missing)`.

#### Snapshot matrix

| View | States | Modes | ~Count |
|------|--------|-------|--------|
| StoryListView | loading, loaded, error, empty, offline | light + dark | 10 |
| StoryRowView | unseen (badge), all seen, single story | light + dark | 6 |
| StoryPlayerView | photo, video buffering, liked, progress | light + dark | 8 |
| StoryProgressBar | start, middle, end, mixed seen/unseen | light only | 4 |

**Total: ~28 snapshots**

### Test file organization

```
StoriesConcept/
├── StoriesConceptTests/
│   ├── UnitTests/
│   │   ├── StoryPlayerFeatureTests.swift
│   │   └── StoryListFeatureTests.swift
│   ├── IntegrationTests/
│   │   └── StoryFlowIntegrationTests.swift
│   └── Helpers/
│       ├── User+Mocks.swift
│       ├── Story+Mocks.swift
│       └── PexelsDTO+Mocks.swift
├── StoriesConceptSnapshotTests/
│   ├── StoryListSnapshotTests.swift
│   ├── StoryPlayerSnapshotTests.swift
│   ├── ComponentSnapshotTests.swift
│   └── __Snapshots__/           (auto-generated reference images)
```

### Testing dependencies setup example

```swift
@Test
func testTimerStartsOnAppear() async {
    let clock = TestClock()

    let store = TestStore(
        initialState: StoryPlayerFeature.State(
            allUsers: [.mock],
            currentUserIndex: 0,
            currentStoryIndex: 0
        )
    ) {
        StoryPlayerFeature()
    } withDependencies: {
        $0.continuousClock = clock
        $0.cacheClient.isAvailable = { _ in true }
        $0.persistenceClient.markSeen = { _ in }
        $0.prefetchClient.prefetchStories = { _, _ in }
        $0.hapticClient.storyChanged = { }
    }

    await store.send(.onAppear) {
        $0.isTimerRunning = true
    }

    await clock.advance(by: .milliseconds(16))
    await store.receive(\.timerTick) {
        $0.progress = 0.00106  // 16ms / 15000ms
    }

    await store.send(.onDisappear) {
        $0.isTimerRunning = false
    }
}
```

---

## 11. View Migration

### Pattern: `@Bindable var store` replaces `@State var viewModel`

```swift
// BEFORE
struct StoryListView: View {
    @State var viewModel: StoryListViewModel
    var body: some View {
        ForEach(viewModel.users) { ... }
    }
}

// AFTER
struct StoryListView: View {
    @Bindable var store: StoreOf<StoryListFeature>
    var body: some View {
        ForEach(store.users) { ... }
            .onAppear { store.send(.loadMoreIfNeeded(currentIndex: index)) }
    }
}
```

### Player presentation

```swift
.fullScreenCover(
    item: $store.scope(state: \.player, action: \.player)
) { playerStore in
    StoryPlayerView(store: playerStore)
}
```

### Gesture handling

```swift
// Actions replace direct method calls
.onTapGesture { location in
    if location.x > geometry.size.width / 2 {
        store.send(.tappedRight)
    } else {
        store.send(.tappedLeft)
    }
}
```

---

## 12. File Structure (Post-Migration)

```
StoriesConcept/
├── App/
│   └── StoriesConceptApp.swift
├── Features/
│   ├── App/
│   │   └── AppFeature.swift
│   ├── StoryList/
│   │   ├── StoryListFeature.swift
│   │   ├── StoryListView.swift
│   │   └── StoryRowView.swift
│   └── StoryPlayer/
│       ├── StoryPlayerFeature.swift
│       ├── StoryPlayerView.swift
│       ├── StoryProgressBar.swift
│       └── VideoPlayerView.swift
├── Dependencies/
│   ├── PexelsClient.swift
│   ├── CacheClient.swift
│   ├── PersistenceClient.swift
│   ├── PrefetchClient.swift
│   ├── HapticClient.swift
│   └── NetworkClient.swift
├── Models/
│   ├── DTOs/
│   │   ├── PexelsPhotoResponse.swift
│   │   └── PexelsVideoResponse.swift
│   ├── Domain/
│   │   ├── User.swift
│   │   ├── Story.swift
│   │   └── MediaType.swift
│   └── Persistence/
│       ├── PersistedUser.swift
│       └── StoryState.swift
├── Utilities/
│   ├── Constants.swift
│   ├── Logger+Extensions.swift
│   └── UserGenerator.swift
```

---

## 13. Migration Order (Bottom-Up)

| Step | What | Depends on |
|------|------|-----------|
| 1 | Add SPM dependencies (TCA, swift-sharing, swift-snapshot-testing) | — |
| 2 | Add Equatable conformance to domain models + DTOs | — |
| 3 | Create Logger+Extensions.swift | — |
| 4 | Extract UserGenerator utility from StoryListViewModel | — |
| 5 | Create all 6 Dependency clients (protocols + live + test + preview) | Steps 1, 2 |
| 6 | Create StoryPlayerFeature reducer | Step 5 |
| 7 | Create StoryListFeature reducer with @Presents | Steps 5, 6 |
| 8 | Create AppFeature composition root | Step 7 |
| 9 | Migrate Views to use Store | Steps 6, 7, 8 |
| 10 | Write unit tests (exhaustive) | Steps 6, 7 |
| 11 | Write integration tests (non-exhaustive) | Step 9 |
| 12 | Write snapshot tests | Step 9 |
| 13 | Remove old ViewModels and Services | Steps 9-12 passing |
| 14 | Final cleanup, verify all tests pass | Step 13 |

---

## 14. Constraints & Non-Goals

### Constraints (carried from original spec)
- No references to BeReal or Voodoo anywhere
- Images from Pexels API (not static assets)
- Max 5 HTTP requests total (3 block 0 + 2 block 1)
- API key in code (acceptable for test scope)
- iOS 17+ minimum

### Non-goals for this migration
- SPM modularization (monolith with folder structure)
- SwiftData replacement (retained as persistence layer)
- TCA 2.0 migration (using stable 1.25.1 APIs)
- New features (migration only, no new functionality)

---

## 15. Glossary — TCA Concepts

For reference during implementation:

| Concept | What it is | MVVM equivalent |
|---------|-----------|-----------------|
| **Reducer** | Pure function: (State, Action) → (State, Effect) | ViewModel |
| **State** | Value type (struct) holding all feature data | ViewModel's @Published properties |
| **Action** | Enum describing everything that can happen | ViewModel methods + callbacks |
| **Effect** | Async work (network, disk, timers) returned from reducer | async methods in ViewModel |
| **Store** | Runtime that holds state and processes actions | ViewModel instance |
| **Scope** | Derives a child store from a parent store | Passing sub-ViewModel |
| **@Dependency** | Injected service, swappable in tests | Constructor-injected service |
| **DependencyKey** | Registration of live/test/preview implementations | Protocol + implementations |
| **@ObservableState** | Makes State observable by SwiftUI | @Observable on ViewModel |
| **@Presents** | Optional child state for modal presentation | Boolean + fullScreenCover |
| **PresentationAction** | Wraps child actions with present/dismiss lifecycle | — |
| **TestStore** | Test harness that asserts every state change | — (no equivalent) |
| **exhaustivity** | Whether tests must assert ALL changes or just some | — |
| **withDependencies** | Override dependencies for a scope (test/preview) | Mock injection |
| **`unimplemented()`** | Closure that crashes if called — forces explicit test setup | — |
| **`.cancellable(id:)`** | Tags an effect for later cancellation | Task.cancel() |
| **delegate action** | Child → parent communication without coupling | Closure callback |
