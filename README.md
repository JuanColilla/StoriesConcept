# StoriesConcept

A native iOS app that replicates the Instagram Stories experience — full-screen, swipeable, ephemeral content — built entirely in **SwiftUI** with no third-party dependencies.

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

**MVVM** with Swift's `@Observable` macro (iOS 17+).

```
Views → ViewModels → Services → Models/Persistence
```

| Layer | Components |
|---|---|
| **Views** | `StoryListView`, `StoryPlayerView`, `StoryRowView`, `StoryProgressBar`, `VideoPlayerView` |
| **ViewModels** | `StoryListViewModel`, `StoryPlayerViewModel` |
| **Services** | `PexelsService`, `CacheService`, `PrefetchService`, `PersistenceService`, `HapticService`, `NetworkMonitor` |
| **Models** | Domain (`User`, `Story`), DTOs (Pexels API responses), Persistence (`PersistedUser`, `StoryState`) |

### Key design decisions

- **Composite story ID** (`userId_mediaId_blockIndex`) — separates content identity (cache key) from story identity (seen/liked state), allowing the same Pexels media to appear for different users without cache collisions.
- **Block-based generation** — users are generated in blocks of 10. Blocks 0–1 fetch from the API; block 2+ recycles the existing content pool with shuffled rotation to maximize variety.
- **API-agnostic domain models** — DTOs map Pexels responses; domain models (`Story`, `User`) are source-agnostic, making it easy to swap the content provider.
- **View identity via `.id(story.id)`** — forces SwiftUI to destroy and recreate `VideoPlayerView` on story change, preventing stale AVPlayer instances from playing the wrong content.

## Tech Stack

| | |
|---|---|
| **Platform** | iOS 17+ |
| **UI** | SwiftUI |
| **Persistence** | SwiftData |
| **Video** | AVFoundation / AVKit |
| **Networking** | URLSession (async/await) |
| **Connectivity** | Network framework (`NWPathMonitor`) |

Zero third-party dependencies.

## Getting Started

1. Clone the repository
2. Open `StoriesConcept.xcodeproj` in Xcode 16+
3. Build and run on a simulator or device (iOS 17+)

> The Pexels API key is bundled in the source for convenience. For production use, move it to a secure configuration.

## Project Structure

```
StoriesConcept/
├── StoriesConceptApp.swift       # App entry point, SwiftData container setup
├── Models/
│   ├── DTOs/                     # Pexels API response models
│   ├── Domain/                   # User, Story, MediaType
│   └── Persistence/              # SwiftData models (PersistedUser, StoryState)
├── ViewModels/
│   ├── StoryListViewModel.swift  # User list, pagination, content generation
│   └── StoryPlayerViewModel.swift# Playback state, timer, navigation
├── Views/
│   ├── StoryListView.swift       # Scrollable user list with offline banner
│   ├── StoryPlayerView.swift     # Full-screen player with gestures
│   ├── StoryRowView.swift        # User row with avatar and unseen count
│   ├── StoryProgressBar.swift    # Segmented progress indicator
│   └── VideoPlayerView.swift     # AVPlayerViewController bridge
├── Services/
│   ├── PexelsService.swift       # API client
│   ├── CacheService.swift        # Two-level media cache
│   ├── PrefetchService.swift     # Thumbnail + story prefetching
│   ├── PersistenceService.swift  # SwiftData CRUD + in-memory state cache
│   ├── HapticService.swift       # Haptic feedback
│   └── NetworkMonitor.swift      # NWPathMonitor wrapper
└── Utilities/
    └── Constants.swift           # Configuration values
```

## Author

**Juan Colilla** — [GitHub](https://github.com/JuanColilla)
