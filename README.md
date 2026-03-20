# StoriesConcept

A native iOS app that replicates the Instagram Stories experience — full-screen, swipeable, ephemeral content — built in **SwiftUI** with **The Composable Architecture (TCA)**.

Content is sourced dynamically from the [Pexels API](https://www.pexels.com/api/) (photos and videos), so every session features real, high-quality media.

## Features

- **Full-screen story player** with segmented progress bar, auto-advance, and user-to-user navigation
- **Photo & video stories** — videos play inline with AVPlayer, including buffering detection and loading indicators
- **Gestures** — tap left/right to navigate stories, swipe horizontally between users, swipe down to dismiss, long press to pause
- **Like & seen state** — persisted with SwiftData across sessions
- **Infinite scroll** — users are generated in blocks of 10; content is recycled after the initial API calls to stay within rate limits
- **Two-level cache** — NSCache (memory, 50 items / 100 MB) + FileManager (disk, 24h TTL) for all media
- **Smart prefetching** — thumbnails prefetched in the list, adjacent stories prefetched in the player
- **Offline support** — cached content remains available without connectivity; a bottom banner indicates connection status
- **Pull-to-refresh** — generates a fresh block of stories prepended to the list
- **Connectivity recovery** — automatically retries content loading when the network is restored
- **Image downsampling** — `CGImageSourceCreateThumbnailAtIndex` prevents full-resolution decoding spikes

## Architecture

### Variations

The project has two architectural approaches, each on its own branch:

| Branch | Architecture | Description |
|---|---|---|
| `main` | **MVVM** | `@Observable` macro (iOS 17+), ViewModels, Services |
| `variation/composableArchitecture` | **TCA** | Reducers, Effects, `@Dependency`, `@Shared` state |

### MVVM (main)

```
Views → ViewModels → Services → Models/Persistence
```

| Layer | Components |
|---|---|
| **Views** | `StoryListView`, `StoryPlayerView`, `StoryRowView`, `StoryProgressBar`, `VideoPlayerView` |
| **ViewModels** | `StoryListViewModel`, `StoryPlayerViewModel` |
| **Services** | `PexelsService`, `CacheService`, `PrefetchService`, `PersistenceService`, `HapticService`, `NetworkMonitor` |
| **Models** | Domain (`User`, `Story`), DTOs (Pexels API responses), Persistence (`PersistedUser`, `StoryState`) |

### TCA (variation/composableArchitecture)

```
Views → Store<Feature> → Reducer → Effects → Dependencies
```

| Layer | Components |
|---|---|
| **Features** | `StoryListFeature` (Reducer + State + Action), `StoryPlayerFeature` |
| **Views** | `StoryListView`, `StoryPlayerView`, `StoryRowView`, `StoryProgressBar`, `VideoPlayerView` |
| **Dependencies** | `PexelsClient`, `CacheClient`, `PrefetchClient`, `PersistenceClient`, `HapticClient`, `NetworkClient` |
| **Shared State** | `@Shared(.inMemory("seenIds"))`, `@Shared(.inMemory("likedIds"))` |

Navigation uses `@Presents` with `.ifLet` for the modal player. All side effects are managed through TCA's `Effect` system with cancellation IDs.

### Key design decisions

- **Composite story ID** (`userId_mediaId_blockIndex`) — separates content identity (cache key) from story identity (seen/liked state), allowing the same Pexels media to appear for different users without cache collisions.
- **Block-based generation** — users are generated in blocks of 10. Blocks 0–1 fetch from the API; block 2+ recycles the existing content pool with shuffled rotation to maximize variety.
- **API-agnostic domain models** — DTOs map Pexels responses; domain models (`Story`, `User`) are source-agnostic, making it easy to swap the content provider.
- **View identity via `.id(story.id)`** — forces SwiftUI to destroy and recreate `VideoPlayerView` on story change, preventing stale AVPlayer instances from playing the wrong content.

## Testing

The TCA branch includes a comprehensive test suite:

### Unit Tests (31 tests)

Using **Swift Testing** (`@Test`, `@Suite`) with TCA's `TestStore`:

| Suite | Tests | Coverage |
|---|---|---|
| `StoryPlayerFeatureTests` | 18 | Timer/playback, navigation, likes, seen tracking, dismiss |
| `StoryListFeatureTests` | 10 | Initial load, error handling, pagination, cache bootstrap, player presentation |
| `StoryFlowIntegrationTests` | 3 | Full viewing flow, like persistence, seen state sync |

### Snapshot Tests (28 tests)

Using [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — every view state in light and dark mode:

| Suite | Tests | States |
|---|---|---|
| `StoryRowViewSnapshotTests` | 6 | Unseen, all seen, single unseen |
| `StoryProgressBarSnapshotTests` | 8 | Beginning, mid-progress, near-end, single segment |
| `StoryListViewSnapshotTests` | 10 | Loading, error, populated unseen, populated mixed, empty |
| `StoryPlayerViewSnapshotTests` | 12 | Default, mid-progress, liked, content loading, last story, second user |

```bash
# Run all tests
xcodebuild test -project StoriesConcept.xcodeproj -scheme StoriesConcept \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Tech Stack

| | |
|---|---|
| **Platform** | iOS 17+ |
| **UI** | SwiftUI |
| **Architecture** | MVVM (`main`) / TCA 1.25.1 (`variation/composableArchitecture`) |
| **Persistence** | SwiftData |
| **Video** | AVFoundation / AVKit |
| **Networking** | URLSession (async/await) |
| **Connectivity** | Network framework (`NWPathMonitor`) |
| **Testing** | Swift Testing, swift-snapshot-testing |

## Getting Started

1. Clone the repository
2. Open `StoriesConcept.xcodeproj` in Xcode 16+
3. **Trust Swift Macros** — on first build, Xcode will prompt to approve macros from TCA's dependencies (CasePathsMacros, ComposableArchitectureMacros, PerceptionMacros, DependenciesMacrosPlugin). Click **"Trust & Enable All"** or the project won't compile.
4. Build and run on a simulator or device (iOS 17+)

> The Pexels API key is bundled in the source for convenience. For production use, move it to a secure configuration.

## Project Structure

```
StoriesConcept/
├── StoriesConceptApp.swift
├── Models/
│   ├── DTOs/                     # Pexels API response models
│   ├── Domain/                   # User, Story, MediaType
│   └── Persistence/              # SwiftData models
├── Features/                     # TCA branch only
│   ├── StoryList/                # StoryListFeature (Reducer)
│   └── StoryPlayer/              # StoryPlayerFeature (Reducer)
├── Dependencies/                 # TCA branch only
│   ├── PexelsClient.swift
│   ├── CacheClient.swift
│   ├── PersistenceClient.swift
│   └── ...
├── Views/
│   ├── StoryListView.swift
│   ├── StoryPlayerView.swift
│   ├── StoryRowView.swift
│   ├── StoryProgressBar.swift
│   └── VideoPlayerView.swift
├── Services/                     # MVVM branch only
│   ├── PexelsService.swift
│   ├── CacheService.swift
│   └── ...
└── Utilities/
    └── Constants.swift

StoriesConceptTests/              # TCA unit + integration tests
StoriesConceptSnapshotTests/      # Snapshot tests (light/dark)
└── __Snapshots__/                # Reference images
```

## Author

**Juan Colilla** — [GitHub](https://github.com/JuanColilla)
