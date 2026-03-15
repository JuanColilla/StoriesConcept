# StoriesConcept CLAUDE.md

## Project Context
- Type: personal
- Architecture: swiftui

## STACK
- iOS 17+ (minimum deployment target)
- Swift & SwiftUI
- SwiftData (persistence: user generation + story states)
- AVFoundation (video playback)
- Pexels API (photos + videos content source)

## COMMANDS
```bash
# Build
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build

# Run tests
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator test
```

## ARCHITECTURE
MVVM with `@Observable` (iOS 17 macro).

Full spec: `docs/superpowers/specs/2026-03-15-instagram-stories-design.md`
Design file: `Stories_Design.pen` (Pencil MCP)

### Layers
```
Views → ViewModels → Services → Models/Persistence
```

### Key Components
- **Views:** StoryListView, StoryPlayerView, StoryRowView, StoryProgressBar
- **ViewModels:** StoryListViewModel, StoryPlayerViewModel
- **Services:** PexelsService, CacheService, PrefetchService, PersistenceService, HapticService
- **Models:** DTOs (Pexels API), Domain (User, Story), Persistence (PersistedUser, StoryState)

### Key Patterns
- Composite ID: `userId_mediaId_blockIndex` — separates content identity (cache) from story identity (state)
- Two-level cache: NSCache (memory) + FileManager (disk, 24h TTL)
- Two prefetch strategies: thumbnails (list) + linear (player)
- Seen = playback completed (timer finished OR user advanced), NOT playback started

## DESIGN SYSTEM
- Design reference in `Stories_Design.pen` (access via Pencil MCP tools only)
- No custom design tokens — follows iOS system defaults with dark player background

## CONSTRAINTS
- No references to BeReal or Voodoo anywhere in the codebase
- Images must not be static assets — downloaded from Pexels API
- Pexels API: max 5 HTTP requests total (3 for block 0, 2 for block 1, then recycle)
- API key stored in code (acceptable for test scope, not production)

## LEARNED CORRECTIONS
(none yet)
