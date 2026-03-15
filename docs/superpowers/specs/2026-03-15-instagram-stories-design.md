# Instagram Stories Feature — Design Spec

## Overview

**StoriesConcept** — iOS app implementing an Instagram Stories-like feature. The app displays a vertical list of users with stories, supports infinite pagination, and a fullscreen story player with gestures, likes, seen/unseen tracking, and content prefetching.

**Target:** iOS 17+ | **Language:** Swift & SwiftUI | **Duration:** 4 hours
**Design reference:** `Stories_Design.pen` (accessible via Pencil MCP)

---

## Architecture

**Pattern:** MVVM with `@Observable` (iOS 17 macro)

```
┌─────────────────────────────────────┐
│              Views                  │
│  StoryListView  ·  StoryPlayerView │
│  StoryRowView   ·  StoryProgressBar│
├─────────────────────────────────────┤
│           ViewModels                │
│  StoryListViewModel                │
│  StoryPlayerViewModel              │
├─────────────────────────────────────┤
│            Services                 │
│  PexelsService     CacheService    │
│  PrefetchService   PersistenceService│
│  HapticService                     │
├─────────────────────────────────────┤
│             Models                  │
│  DTOs: PexelsPhotoResponse,        │
│        PexelsVideoResponse         │
│  Domain: User, Story, MediaType    │
│  Persistence: PersistedUser,       │
│               StoryState (SwiftData)│
└─────────────────────────────────────┘
```

---

## Models

### DTOs (Data Transfer Objects)

Structures that map Pexels API responses field-by-field. Their only job is to decode JSON. They do NOT contain app logic.

**Photo endpoints:**
- **`PexelsPhotoResponse`** — `photos: [PexelsPhoto]`, `page: Int`, `per_page: Int`, `next_page: String?`
- **`PexelsPhoto`** — `id: Int`, `width: Int`, `height: Int`, `photographer: String`, `avg_color: String`, `src: PexelsSrc`
- **`PexelsSrc`** — `original: String`, `large2x: String`, `large: String`, `medium: String`, `small: String`, `portrait: String`, `landscape: String`, `tiny: String`

**Video endpoints:**
- **`PexelsVideoResponse`** — `videos: [PexelsVideo]`, `page: Int`, `per_page: Int`, `next_page: String?`
- **`PexelsVideo`** — `id: Int`, `width: Int`, `height: Int`, `duration: Int`, `image: String` (poster/screenshot URL), `video_files: [PexelsVideoFile]`
- **`PexelsVideoFile`** — `id: Int`, `quality: String`, `file_type: String`, `width: Int`, `height: Int`, `fps: Double`, `link: String`

### Domain Models

App-internal models. Decoupled from the API — if Pexels changes, only DTOs change.

- **`User`** — `id: String`, `displayName: String` (e.g. `emma_47`), `avatarURL: URL` (profile photo from Pexels), `stories: [Story]`
- **`Story`** — `id: String` (composite: `userId_mediaId_blockIndex`), `mediaURL: URL`, `type: MediaType`, `duration: TimeInterval` (15s for photos, capped at 45s for videos), `postedAt: Date` (generated timestamp)
- **`MediaType`** — Enum: `.photo`, `.video`

### Persistence Models (SwiftData)

- **`PersistedUser`** — `id: String`, `displayName: String`, `blockIndex: Int`, `avatarURL: String`, `stories: [PersistedStory]` (Codable array, not parallel arrays)
- **`PersistedStory`** — Codable struct (not a SwiftData model): `pexelsMediaId: String`, `mediaURL: String`, `mediaType: String`, `duration: TimeInterval`, `postedAt: Date`
- **`StoryState`** — SwiftData model: `storyId: String` (composite ID, primary key), `isLiked: Bool`, `isSeen: Bool`, `seenAt: Date`

### Composite ID Strategy

```
Story ID = "\(userId)_\(pexelsMediaId)_\(blockIndex)"
```

- **Content cache key** = `pexelsMediaId` → same photo downloaded once, regardless of which user it's assigned to
- **State key** = composite `storyId` → like/seen state is unique per story-user assignment
- Recycled content (block 2+) gets new composite IDs, so states don't collide

---

## Services

### `PexelsService` — Networking

- Calls Pexels API for photos, videos, and avatar photos
- Returns DTOs only — no app logic
- Manages API key via `Authorization` header
- **Endpoints used:**
  - `GET /v1/curated?page={n}&per_page=40` — curated photos for story content
  - `GET /videos/popular?page={n}&per_page=20` — popular videos for story content
  - `GET /v1/search?query=portrait+face&page={n}&per_page=50` — face photos for user avatars
- Supports pagination: receives page number, returns results + `next_page` URL

### `CacheService` — Multimedia Content Cache

- **Two levels:** `NSCache` (in-memory, fast access) + `FileManager` (disk, survives app restart)
- **24-hour TTL:** when saving to disk, records timestamp in a metadata plist alongside the file. On read, discards if >24h old
- **Cache key:** `pexelsMediaId` (not composite ID) — same photo shared by multiple users is stored once
- **NSCache limits:** configure `countLimit` and `totalCostLimit` to prevent memory pressure. When NSCache evicts, the item is still on disk — next access reads from disk and re-populates NSCache
- **Interface:** `save(data:, for mediaId:)`, `load(mediaId:) -> Data?`, `isAvailable(mediaId:) -> Bool`

### `PrefetchService` — Content Prefetching

Two modes of operation for two different contexts:

1. **Thumbnail prefetch (list screen):** `prefetchThumbnails(for visibleUsers: [User])` — downloads only the first story's image for each visible user. Lightweight, parallel downloads.
2. **Linear prefetch (player screen):** `prefetchStories(currentUser:, nextUser:)` — downloads all content for current user + all content for next user. Heavier, prioritized sequentially.

- Uses `CacheService` internally — checks cache before downloading
- Runs on `Task` with `.background` priority — never blocks UI
- If user navigates ahead of prefetch, ViewModel shows loading indicator

### `PersistenceService` — SwiftData Wrapper

- CRUD for `StoryState`: save/read like and seen states
- CRUD for `PersistedUser`: save/read generated users
- Queries by composite `storyId`
- Encapsulates `ModelContainer` and `ModelContext` — ViewModels never touch SwiftData directly
- Provides: `firstUnseenIndex(for user:) -> Int`, `unseenCount(for user:) -> Int`, `allSeen(for user:) -> Bool`

### `HapticService` — Haptic Feedback

- `storyChanged()` → `UIImpactFeedbackGenerator(.light)` — subtle tap between stories
- `userChanged()` → `UIImpactFeedbackGenerator(.medium)` — noticeable bump when switching users
- `liked()` → `UINotificationFeedbackGenerator(.success)` — satisfying "pop" for like/unlike

---

## ViewModels

### `StoryListViewModel`

- Loads persisted users. If none exist (first launch), generates first block from Pexels
- **User generation:** picks from a hardcoded list of ~50 unique names (English, Spanish, French) + random 2-4 digit suffix → `emma_47`, `carlos_823`. Each user gets 1-10 random stories from Pexels content
- **10 users per block** of pagination
- **Infinite pagination:** maintains `blockIndex`. Blocks 0-1 call Pexels API for real content. Block 2+ recycles existing content with new composite IDs
- **Generated users are persisted immediately** in SwiftData (`PersistedUser`) — once created, a user is immutable
- Requests thumbnail prefetch for visible users via `PrefetchService`
- Queries `PersistenceService` for seen/unseen state per user
- **Exposed state:** `users: [User]`, `loadMoreIfNeeded(currentUser:)`, `unseenCount(for user:) -> Int`, `allSeen(for user:) -> Bool`

### `StoryPlayerViewModel`

- Receives: selected user, index in global user list, starting story index (from `firstUnseenIndex`)
- **Timer control:** 15s for photos, actual duration for videos (capped at 45s). Pauses on: long press, content not loaded yet, app backgrounding. Auto-advances to next story when complete; if last story of user → auto-advances to next user
- **Like/unlike:** updates `PersistenceService`, exposes current state
- **Marks stories as seen** when playback completes (timer finishes OR user manually advances to next story). A story is NOT marked seen just because it started playing — only when the user has fully consumed it or explicitly skipped forward
- **Prefetch:** requests linear prefetch (current user + next user) via `PrefetchService`
- **Navigation:** tap right = next story, tap left = previous story, swipe horizontal = change user, swipe down / tap X = close
- **Resume logic:** if user has unseen stories, opens at first unseen. If all seen, opens at first story (seen states remain unchanged — re-watching does not reset seen)
- **Edge case — last loaded user:** if swiping next on the last loaded user, triggers `loadMoreIfNeeded` via a callback to `StoryListViewModel`. Shows loading indicator while new users generate
- **Exposed state:** `currentStory: Story`, `progress: Double`, `isLiked: Bool`, `isLoading: Bool`, `stories: [Story]`, `currentIndex: Int`

---

## Views

### `StoryListView` — Main Screen

- Title "Stories" at top
- `ScrollView` + `LazyVStack` vertical list of `StoryRowView` items
- Each row: circular avatar (user profile photo), username, and right-side indicator
- On appear of each row → requests thumbnail prefetch for first story
- Near end of scroll → triggers `loadMoreIfNeeded()` for infinite pagination
- Tap on row → opens `StoryPlayerView` via `.fullScreenCover`

### `StoryRowView` — User Row Component

- **Avatar:** circular user profile photo with green ring border if unseen stories exist, no ring if all seen
- **Username:** displayed next to avatar
- **Right indicator:** green badge with unseen count (e.g. "3") if stories pending, or "Seen" text in grey if all viewed
- Pure component: receives `User` + seen state, no ViewModel dependency

### `StoryPlayerView` — Fullscreen Player

- Content fills entire screen (`.ignoresSafeArea`), dark background
- **Top:** `StoryProgressBar` (segmented), below it: avatar + username + timestamp ("2h ago") on left, X button on right
- **Center:** photo/video fullscreen. If not cached yet → `ProgressView` centered, timer paused, but navigation still works
- **Bottom right:** like button (heart outline / filled with animation)
- **Seen/unseen visual state:** the progress bar segments reflect whether each story was previously completed (seen) or not. This is based on prior completed playback, not the current viewing session. A story currently playing is not yet "seen" until it completes or the user advances past it
- **Gestures:**
  - `TapGesture` with location detection → right side (>50% width) = next story, left side = previous
  - `DragGesture` horizontal (min distance threshold to avoid conflict with tap) → change user with slide transition
  - `LongPressGesture` → pause timer (resume on release)
  - `DragGesture` vertical down / X button → close player

### `StoryProgressBar` — Reusable Component

- Receives: total segments, active index, active progress (0.0 to 1.0)
- Past segments: fully filled white
- Active segment: fills progressively
- Future segments: semi-transparent white background
- All segments have rounded corners, small gap between them

---

## Data Flow

### First Launch
1. App opens → `StoryListViewModel` checks `PersistenceService` for existing users → none found
2. Calls `PexelsService` for page 1 of photos (`/v1/curated?per_page=40`), page 1 of videos (`/videos/popular?per_page=20`), and avatar photos (`/v1/search?query=portrait+face&per_page=50`) → 3 HTTP requests
3. Generates block 0 of users (10 users): picks names from hardcoded list, assigns random suffix, assigns avatar from portrait pool, assigns 1-10 random stories from photo+video content pool, generates random `postedAt` timestamp (1-24h ago)
4. Persists users in SwiftData (`PersistedUser`)
5. Displays list, starts prefetching thumbnails for visible users

### Infinite Pagination
1. User scrolls near bottom → `loadMoreIfNeeded()` triggered
2. Block 0: initial load (see First Launch). Block 1: calls `PexelsService` for page 2 of photos + videos (2 HTTP requests), generates 10 new users with fresh content
3. Block 2+: recycles content from blocks 0-1, generates 10 new users with new composite IDs. No API calls
4. New users persisted immediately

### Total API Calls
- Block 0: 3 requests (photos page 1 + videos page 1 + avatars)
- Block 1: 2 requests (photos page 2 + videos page 2)
- Block 2+: 0 requests (recycled content)
- **Total: 5 HTTP requests maximum**, well within rate limits (200/hour, 20,000/month)

### Opening Stories
1. User taps a row → `StoryListViewModel` calculates `firstUnseenIndex` for that user
2. Opens `StoryPlayerView` with user, position in list, and starting index
3. `StoryPlayerViewModel` starts timer, marks current story as seen, requests linear prefetch
4. Player shows content from cache if available, loading indicator if not (timer paused)

### Navigation in Player
1. Tap right / timer ends → next story in same user. If last story → auto-advance to next user
2. Tap left → previous story. If first story → stay (no wrap)
3. Swipe horizontal → change user with slide transition. Triggers new prefetch for new current + next user
4. Swipe down / X → close, return to list. List refreshes seen states immediately

---

## User Generation

### Hardcoded Name Pool (~50 unique names)

**English:** emma, jake, sophie, oliver, mia, noah, lily, max, hannah, ryan, zoe, tyler, grace, mason, aria, logan, ella, connor

**Spanish:** carlos, sofia, alejandro, valentina, diego, camila, mateo, isabella, santiago, paula, daniel, lucia, andres, elena, pablo, maria, javier, carmen, rafael, alba

**French:** hugo, manon, louis, léa, jules, arthur, lucas, camille, gabriel, louise, raphaël, alice, théo, inès, léon, jade, antoine, margot

### Generation Rules
- Pick name from combined pool (no repeat within same block, no cross-block repeat check needed since suffix makes them unique)
- Append `_` + random 2-4 digit number → `emma_47`, `carlos_823`, `sophie_1294`
- Assign avatar from portrait photo pool (one per user, persisted)
- Assign 1-10 random stories from available Pexels content (mix of photos and videos)
- Generate random `postedAt` timestamp between 1-24 hours ago for each story
- Persist immediately — user is immutable once generated

---

## Error Handling

### Network Errors
- **API call fails:** show inline error state with "Retry" button on the list screen. Already-loaded users remain visible and functional
- **No connection on first launch:** show fullscreen error with retry button (no cached users exist yet)
- **Prefetch fails:** silently skip — when user navigates to that story, show loading indicator and retry the download on demand
- **Rate limit hit (429):** treat as network error, show retry. Unlikely given our 5-request maximum

### Cache Errors
- **NSCache eviction (memory pressure):** transparent to user — next access reads from disk and re-populates NSCache
- **Disk cache miss (expired or deleted):** re-download from Pexels on demand. Show loading indicator in player
- **Disk full:** degrade gracefully — NSCache-only mode, content not persisted to disk

---

## Cache & Persistence Summary

| What | Where | Key | TTL |
|------|-------|-----|-----|
| Media files (photos/videos) | NSCache + FileManager | `pexelsMediaId` | 24 hours |
| User generation | SwiftData (`PersistedUser`) | `userId` | Permanent |
| User avatars | CacheService (same as media) | `avatar_pexelsPhotoId` | 24 hours |
| Story states (like, seen) | SwiftData (`StoryState`) | composite `storyId` | Permanent |

---

## Haptic Feedback

| Action | Generator | Style |
|--------|-----------|-------|
| Next/previous story (tap) | `UIImpactFeedbackGenerator` | `.light` |
| Change user (swipe) | `UIImpactFeedbackGenerator` | `.medium` |
| Like/unlike | `UINotificationFeedbackGenerator` | `.success` |

---

## API: Pexels

- **Base URL:** `https://api.pexels.com`
- **Auth:** `Authorization: {API_KEY}` header on every request
- **Rate limit:** 200 requests/hour, 20,000 requests/month. Response headers: `X-Ratelimit-Limit`, `X-Ratelimit-Remaining`, `X-Ratelimit-Reset`

### Endpoints Used

| Endpoint | Purpose | Per Page | Pages Used |
|----------|---------|----------|------------|
| `GET /v1/curated` | Photos for stories | 40 | 1-2 |
| `GET /videos/popular` | Videos for stories | 20 | 1-2 |
| `GET /v1/search?query=portrait+face` | User avatar photos | 50 | 1 |

### Photo Response Key Fields
- `id`, `src.portrait` (fullscreen stories), `src.medium` (thumbnails), `avg_color` (placeholder)

### Video Response Key Fields
- `id`, `image` (poster/thumbnail), `duration` (seconds, capped at 45s in app), `video_files[].link` (select HD quality ≤1080p, prefer H.264/mp4)

### Development Mock Strategy
- Save real API responses as local JSON files during initial development
- Switch to live API for final testing and submission
- Mock files replicate exact Pexels response structure for seamless swap

---

## Out of Scope (Justified)

- **Story creation:** read-only consumption
- **Real authentication:** no user accounts
- **Push notifications:** not relevant for the feature
- **iPad/landscape support:** iPhone portrait only for scope
- **Custom transitions:** using `.fullScreenCover` with standard animation. Can be enhanced if time permits

---

## Technical Notes

- All prefetching runs on `.background` priority `Task` — UI never blocked
- If content isn't loaded when user navigates to a story, show `ProgressView` and pause timer. Navigation remains fully functional
- Timer pauses on: long press, content loading, app backgrounding
- On app foreground after extended background: player resumes where it left off, no data staleness concern (content is static)
- Video playback via `AVPlayer` wrapped in a SwiftUI view
- Video quality selection: prefer `video_files` entry with `quality: "hd"`, `file_type: "video/mp4"`, `height <= 1080`. Fallback to largest available if no match
- Images displayed from cache (`CacheService`), not via `AsyncImage` (which bypasses our cache)
- Downsampling images with `CGImageSourceCreateThumbnailAtIndex` for memory efficiency
- Gesture priority: `LongPressGesture` > `DragGesture` (min distance 20pt) > `TapGesture` — prevents conflicts between tap and swipe
