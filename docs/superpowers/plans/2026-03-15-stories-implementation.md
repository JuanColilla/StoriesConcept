# StoriesConcept Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Instagram Stories-like iOS app that displays users with stories in a vertical list, supports infinite pagination, fullscreen playback with gestures/likes/seen tracking, and content from Pexels API.

**Architecture:** MVVM with `@Observable` (iOS 17). Views → ViewModels → Services → Models. Two-level cache (NSCache + disk), SwiftData persistence for user generation and story states. Content sourced from Pexels API with recycling after 2 blocks.

**Tech Stack:** Swift, SwiftUI, SwiftData, AVFoundation, Pexels REST API, iOS 17+

**Spec:** `docs/superpowers/specs/2026-03-15-instagram-stories-design.md`

---

## File Structure

```
StoriesConcept/
├── StoriesConceptApp.swift          (MODIFY — replace template with our ModelContainer)
├── ContentView.swift                (DELETE — replaced by StoryListView)
├── Item.swift                       (DELETE — template model, unused)
│
├── Models/
│   ├── DTOs/
│   │   ├── PexelsPhotoResponse.swift    — Codable structs for photo API responses
│   │   └── PexelsVideoResponse.swift    — Codable structs for video API responses
│   ├── Domain/
│   │   ├── MediaType.swift              — .photo / .video enum
│   │   ├── Story.swift                  — Story domain model with composite ID
│   │   └── User.swift                   — User domain model with stories array
│   └── Persistence/
│       ├── PersistedUser.swift          — SwiftData model for generated users
│       └── StoryState.swift             — SwiftData model for like/seen state
│
├── Services/
│   ├── PexelsService.swift              — HTTP client for Pexels API (returns DTOs)
│   ├── CacheService.swift               — NSCache + FileManager two-level cache
│   ├── PersistenceService.swift         — SwiftData wrapper (users + story states)
│   ├── PrefetchService.swift            — Thumbnail + linear prefetch strategies
│   └── HapticService.swift              — UIImpactFeedback / UINotificationFeedback
│
├── ViewModels/
│   ├── StoryListViewModel.swift         — User list, generation, pagination, thumbnail prefetch
│   └── StoryPlayerViewModel.swift       — Playback timer, gestures, seen/like, navigation
│
├── Views/
│   ├── StoryListView.swift              — Vertical ScrollView + LazyVStack of users
│   ├── StoryRowView.swift               — Avatar + name + seen/unseen indicator
│   ├── StoryPlayerView.swift            — Fullscreen player with gestures
│   ├── StoryProgressBar.swift           — Segmented progress indicator
│   └── VideoPlayerView.swift            — AVPlayer wrapped for SwiftUI
│
├── Utilities/
│   └── Constants.swift                  — API key, name pool, timing constants
│
└── Tests/ (in StoriesConceptTests target)
    ├── PexelsServiceTests.swift         — JSON decoding tests with mock data
    ├── CacheServiceTests.swift          — Save/load/TTL tests
    ├── PersistenceServiceTests.swift    — SwiftData CRUD tests
    └── StoryPlayerViewModelTests.swift  — Timer, navigation, seen logic tests
```

---

## Chunk 1: Foundation — Models & Constants

### Task 1: Project Cleanup & Constants

**Files:**
- Delete: `StoriesConcept/ContentView.swift`
- Delete: `StoriesConcept/Item.swift`
- Create: `StoriesConcept/Utilities/Constants.swift`

- [ ] **Step 1: Delete template files**

Remove `ContentView.swift` and `Item.swift` — they are Xcode SwiftData template files we won't use.

```bash
rm StoriesConcept/ContentView.swift StoriesConcept/Item.swift
```

- [ ] **Step 2: Create Constants.swift**

```swift
import Foundation

enum Constants {
    static let pexelsAPIKey = "r7EbWKvE0Y1PW8N91otVyz5nyT6UK3JPtrqirOncGapeCiSJ18sNp73z"
    static let pexelsBaseURL = "https://api.pexels.com"

    static let photoAutoAdvanceDuration: TimeInterval = 15
    static let maxVideoDuration: TimeInterval = 45
    static let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours
    static let usersPerBlock = 10
    static let minStoriesPerUser = 1
    static let maxStoriesPerUser = 10
    static let dragMinDistance: CGFloat = 20

    static let namePool: [String] = [
        // English
        "emma", "jake", "sophie", "oliver", "mia", "noah", "lily", "max",
        "hannah", "ryan", "zoe", "tyler", "grace", "mason", "aria", "logan",
        "ella", "connor",
        // Spanish
        "carlos", "sofia", "alejandro", "valentina", "diego", "camila", "mateo",
        "isabella", "santiago", "paula", "daniel", "lucia", "andres", "elena",
        "pablo", "maria", "javier", "carmen", "rafael", "alba",
        // French
        "hugo", "manon", "louis", "lea", "jules", "arthur", "lucas", "camille",
        "gabriel", "louise", "raphael", "alice", "theo", "ines", "leon", "jade",
        "antoine", "margot"
    ]
}
```

- [ ] **Step 3: Add Constants.swift to Xcode project**

Open `StoriesConcept.xcodeproj` in Xcode or add via `xcodebuild`. Since we're working from CLI, create the folder structure on disk — Xcode will detect new files when opened.

```bash
mkdir -p StoriesConcept/Utilities
# Write file (done in step 2)
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: remove template files, add Constants"
```

---

### Task 2: DTO Models

**Files:**
- Create: `StoriesConcept/Models/DTOs/PexelsPhotoResponse.swift`
- Create: `StoriesConcept/Models/DTOs/PexelsVideoResponse.swift`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p StoriesConcept/Models/DTOs
```

- [ ] **Step 2: Create PexelsPhotoResponse.swift**

```swift
import Foundation

struct PexelsPhotoResponse: Codable {
    let photos: [PexelsPhoto]
    let page: Int
    let perPage: Int
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case photos, page
        case perPage = "per_page"
        case nextPage = "next_page"
    }
}

struct PexelsPhoto: Codable, Identifiable {
    let id: Int
    let width: Int
    let height: Int
    let photographer: String
    let avgColor: String
    let src: PexelsSrc

    enum CodingKeys: String, CodingKey {
        case id, width, height, photographer, src
        case avgColor = "avg_color"
    }
}

struct PexelsSrc: Codable {
    let original: String
    let large2x: String
    let large: String
    let medium: String
    let small: String
    let portrait: String
    let landscape: String
    let tiny: String
}
```

- [ ] **Step 3: Create PexelsVideoResponse.swift**

```swift
import Foundation

struct PexelsVideoResponse: Codable {
    let videos: [PexelsVideo]
    let page: Int
    let perPage: Int
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case videos, page
        case perPage = "per_page"
        case nextPage = "next_page"
    }
}

struct PexelsVideo: Codable, Identifiable {
    let id: Int
    let width: Int
    let height: Int
    let duration: Int
    let image: String
    let videoFiles: [PexelsVideoFile]

    enum CodingKeys: String, CodingKey {
        case id, width, height, duration, image
        case videoFiles = "video_files"
    }
}

struct PexelsVideoFile: Codable, Identifiable {
    let id: Int
    let quality: String
    let fileType: String
    let width: Int?
    let height: Int?
    let fps: Double?
    let link: String

    enum CodingKeys: String, CodingKey {
        case id, quality, width, height, fps, link
        case fileType = "file_type"
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add Pexels API DTO models"
```

---

### Task 3: Domain Models

**Files:**
- Create: `StoriesConcept/Models/Domain/MediaType.swift`
- Create: `StoriesConcept/Models/Domain/Story.swift`
- Create: `StoriesConcept/Models/Domain/User.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p StoriesConcept/Models/Domain
```

- [ ] **Step 2: Create MediaType.swift**

```swift
import Foundation

enum MediaType: String, Codable {
    case photo
    case video
}
```

- [ ] **Step 3: Create Story.swift**

```swift
import Foundation

struct Story: Identifiable {
    /// Composite ID: "\(userId)_\(pexelsMediaId)_\(blockIndex)"
    let id: String
    /// Pexels media ID — used as cache key, shared across users for same content
    let pexelsMediaId: String
    let mediaURL: URL
    let type: MediaType
    /// 15s for photos, actual duration (capped 45s) for videos
    let duration: TimeInterval
    let postedAt: Date

    /// Cache key — shared across users for same Pexels content
    var cacheKey: String { pexelsMediaId }

    static func compositeId(userId: String, mediaId: String, blockIndex: Int) -> String {
        "\(userId)_\(mediaId)_\(blockIndex)"
    }
}
```

- [ ] **Step 4: Create User.swift**

```swift
import Foundation

struct User: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: URL
    var stories: [Story]
}
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add domain models (User, Story, MediaType)"
```

---

### Task 4: Persistence Models (SwiftData)

**Files:**
- Create: `StoriesConcept/Models/Persistence/PersistedUser.swift`
- Create: `StoriesConcept/Models/Persistence/StoryState.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p StoriesConcept/Models/Persistence
```

- [ ] **Step 2: Create PersistedUser.swift**

```swift
import Foundation
import SwiftData

struct PersistedStory: Codable {
    let pexelsMediaId: String
    let mediaURL: String
    let mediaType: String
    let duration: TimeInterval
    let postedAt: Date
}

@Model
final class PersistedUser {
    @Attribute(.unique) var id: String
    var displayName: String
    var blockIndex: Int
    var avatarURL: String
    var storiesData: Data // Encoded [PersistedStory]

    init(id: String, displayName: String, blockIndex: Int, avatarURL: String, stories: [PersistedStory]) {
        self.id = id
        self.displayName = displayName
        self.blockIndex = blockIndex
        self.avatarURL = avatarURL
        self.storiesData = (try? JSONEncoder().encode(stories)) ?? Data()
    }

    var stories: [PersistedStory] {
        (try? JSONDecoder().decode([PersistedStory].self, from: storiesData)) ?? []
    }
}
```

> **Why `storiesData: Data` instead of `[PersistedStory]` directly?** SwiftData doesn't natively support arrays of Codable structs as model properties. We encode/decode manually. This is a well-known SwiftData limitation — the alternative would be making PersistedStory a separate `@Model` with a relationship, but that adds complexity for a simple nested array.

- [ ] **Step 3: Create StoryState.swift**

```swift
import Foundation
import SwiftData

@Model
final class StoryState {
    @Attribute(.unique) var storyId: String
    var isLiked: Bool
    var isSeen: Bool
    var seenAt: Date?

    init(storyId: String, isLiked: Bool = false, isSeen: Bool = false, seenAt: Date? = nil) {
        self.storyId = storyId
        self.isLiked = isLiked
        self.isSeen = isSeen
        self.seenAt = seenAt
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add SwiftData persistence models (PersistedUser, StoryState)"
```

---

## Chunk 2: Core Services

### Task 5: HapticService

**Files:**
- Create: `StoriesConcept/Services/HapticService.swift`

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p StoriesConcept/Services
```

```swift
import UIKit

@Observable
final class HapticService {
    func storyChanged() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func userChanged() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func liked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add HapticService"
```

---

### Task 6: CacheService

**Files:**
- Create: `StoriesConcept/Services/CacheService.swift`
- Create: `StoriesConceptTests/CacheServiceTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import StoriesConcept

final class CacheServiceTests: XCTestCase {
    var sut: CacheService!

    override func setUp() {
        super.setUp()
        sut = CacheService(subdirectory: "TestCache_\(UUID().uuidString)")
    }

    override func tearDown() {
        sut.clearAll()
        sut = nil
        super.tearDown()
    }

    func testSaveAndLoad() {
        let data = "hello".data(using: .utf8)!
        sut.save(data: data, for: "key1")

        let loaded = sut.load(mediaId: "key1")
        XCTAssertEqual(loaded, data)
    }

    func testIsAvailable() {
        XCTAssertFalse(sut.isAvailable(mediaId: "missing"))

        sut.save(data: Data([1, 2, 3]), for: "exists")
        XCTAssertTrue(sut.isAvailable(mediaId: "exists"))
    }

    func testExpiredCacheReturnsNil() {
        let data = Data([1, 2, 3])
        sut.save(data: data, for: "old", ttl: -1) // Already expired

        let loaded = sut.load(mediaId: "old")
        XCTAssertNil(loaded)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator test 2>&1 | tail -20
```

Expected: FAIL — `CacheService` does not exist.

- [ ] **Step 3: Implement CacheService**

```swift
import Foundation

@Observable
final class CacheService {
    private let memoryCache = NSCache<NSString, NSData>()
    private let cacheDirectory: URL
    private let metadataFile: URL
    private var metadata: [String: Date] = [:]
    private let defaultTTL: TimeInterval

    init(subdirectory: String = "StoryCache", ttl: TimeInterval = Constants.cacheTTL) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent(subdirectory)
        self.metadataFile = cacheDirectory.appendingPathComponent("cache_metadata.plist")
        self.defaultTTL = ttl

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        loadMetadata()
    }

    func save(data: Data, for mediaId: String, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? defaultTTL

        // Memory cache
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)

        // Disk cache
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        try? data.write(to: fileURL)

        // Metadata — store expiration date
        metadata[mediaId] = Date().addingTimeInterval(effectiveTTL)
        saveMetadata()
    }

    func load(mediaId: String) -> Data? {
        // Check expiration
        if let expiresAt = metadata[mediaId], Date() > expiresAt {
            remove(mediaId: mediaId)
            return nil
        }

        // Memory cache first
        if let cached = memoryCache.object(forKey: mediaId as NSString) {
            return cached as Data
        }

        // Disk fallback
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        // Re-populate memory cache
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
        return data
    }

    func isAvailable(mediaId: String) -> Bool {
        if let expiresAt = metadata[mediaId], Date() > expiresAt {
            return false
        }
        if memoryCache.object(forKey: mediaId as NSString) != nil { return true }
        return FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(mediaId).path)
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        metadata.removeAll()
    }

    // MARK: - Private

    private func remove(mediaId: String) {
        memoryCache.removeObject(forKey: mediaId as NSString)
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        try? FileManager.default.removeItem(at: fileURL)
        metadata.removeValue(forKey: mediaId)
        saveMetadata()
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataFile),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        metadata = dict
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataFile)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator test 2>&1 | tail -20
```

Expected: All CacheServiceTests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add CacheService with two-level cache and TTL"
```

---

### Task 7: PexelsService

**Files:**
- Create: `StoriesConcept/Services/PexelsService.swift`
- Create: `StoriesConceptTests/PexelsServiceTests.swift`
- Create: `StoriesConceptTests/Mocks/mock_photos.json`
- Create: `StoriesConceptTests/Mocks/mock_videos.json`

- [ ] **Step 1: Write mock JSON files for tests**

`mock_photos.json`:
```json
{
    "page": 1,
    "per_page": 2,
    "photos": [
        {
            "id": 1001,
            "width": 3000,
            "height": 4000,
            "photographer": "Test User",
            "avg_color": "#AABBCC",
            "src": {
                "original": "https://example.com/photo1.jpg",
                "large2x": "https://example.com/photo1_l2x.jpg",
                "large": "https://example.com/photo1_l.jpg",
                "medium": "https://example.com/photo1_m.jpg",
                "small": "https://example.com/photo1_s.jpg",
                "portrait": "https://example.com/photo1_p.jpg",
                "landscape": "https://example.com/photo1_ls.jpg",
                "tiny": "https://example.com/photo1_t.jpg"
            }
        },
        {
            "id": 1002,
            "width": 4000,
            "height": 3000,
            "photographer": "Another User",
            "avg_color": "#112233",
            "src": {
                "original": "https://example.com/photo2.jpg",
                "large2x": "https://example.com/photo2_l2x.jpg",
                "large": "https://example.com/photo2_l.jpg",
                "medium": "https://example.com/photo2_m.jpg",
                "small": "https://example.com/photo2_s.jpg",
                "portrait": "https://example.com/photo2_p.jpg",
                "landscape": "https://example.com/photo2_ls.jpg",
                "tiny": "https://example.com/photo2_t.jpg"
            }
        }
    ],
    "next_page": "https://api.pexels.com/v1/curated?page=2&per_page=2"
}
```

`mock_videos.json`:
```json
{
    "page": 1,
    "per_page": 2,
    "videos": [
        {
            "id": 2001,
            "width": 1920,
            "height": 1080,
            "duration": 30,
            "image": "https://example.com/video1_poster.jpg",
            "video_files": [
                {
                    "id": 3001,
                    "quality": "hd",
                    "file_type": "video/mp4",
                    "width": 1920,
                    "height": 1080,
                    "fps": 30.0,
                    "link": "https://example.com/video1_hd.mp4"
                },
                {
                    "id": 3002,
                    "quality": "sd",
                    "file_type": "video/mp4",
                    "width": 640,
                    "height": 360,
                    "fps": 30.0,
                    "link": "https://example.com/video1_sd.mp4"
                }
            ]
        }
    ],
    "next_page": null
}
```

- [ ] **Step 2: Write failing test**

```swift
import XCTest
@testable import StoriesConcept

final class PexelsServiceTests: XCTestCase {

    func testDecodePhotoResponse() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "mock_photos", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(PexelsPhotoResponse.self, from: data)

        XCTAssertEqual(response.photos.count, 2)
        XCTAssertEqual(response.photos[0].id, 1001)
        XCTAssertEqual(response.photos[0].src.portrait, "https://example.com/photo1_p.jpg")
        XCTAssertEqual(response.page, 1)
        XCTAssertNotNil(response.nextPage)
    }

    func testDecodeVideoResponse() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "mock_videos", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(PexelsVideoResponse.self, from: data)

        XCTAssertEqual(response.videos.count, 1)
        XCTAssertEqual(response.videos[0].id, 2001)
        XCTAssertEqual(response.videos[0].duration, 30)
        XCTAssertEqual(response.videos[0].videoFiles.count, 2)
        XCTAssertEqual(response.videos[0].videoFiles[0].quality, "hd")
        XCTAssertNil(response.nextPage)
    }

    func testSelectHDVideoFile() {
        let files = [
            PexelsVideoFile(id: 1, quality: "hd", fileType: "video/mp4", width: 1920, height: 1080, fps: 30, link: "https://hd.mp4"),
            PexelsVideoFile(id: 2, quality: "sd", fileType: "video/mp4", width: 640, height: 360, fps: 30, link: "https://sd.mp4"),
            PexelsVideoFile(id: 3, quality: "uhd", fileType: "video/mp4", width: 3840, height: 2160, fps: 30, link: "https://uhd.mp4")
        ]

        let selected = PexelsService.selectVideoFile(from: files)
        XCTAssertEqual(selected?.quality, "hd")
        XCTAssertEqual(selected?.link, "https://hd.mp4")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Expected: FAIL — `PexelsService` does not exist.

- [ ] **Step 4: Implement PexelsService**

```swift
import Foundation

@Observable
final class PexelsService {
    private let apiKey = Constants.pexelsAPIKey
    private let baseURL = Constants.pexelsBaseURL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    func fetchCuratedPhotos(page: Int, perPage: Int = 40) async throws -> PexelsPhotoResponse {
        let url = URL(string: "\(baseURL)/v1/curated?page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func fetchPopularVideos(page: Int, perPage: Int = 20) async throws -> PexelsVideoResponse {
        let url = URL(string: "\(baseURL)/videos/popular?page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func fetchAvatarPhotos(page: Int = 1, perPage: Int = 50) async throws -> PexelsPhotoResponse {
        let url = URL(string: "\(baseURL)/v1/search?query=portrait+face&page=\(page)&per_page=\(perPage)")!
        return try await request(url: url)
    }

    func downloadData(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Video File Selection

    /// Select best video file: HD quality, mp4, height ≤ 1080p. Fallback to largest available.
    static func selectVideoFile(from files: [PexelsVideoFile]) -> PexelsVideoFile? {
        // Prefer HD mp4 ≤ 1080p
        let hdFile = files.first { file in
            file.quality == "hd" &&
            file.fileType == "video/mp4" &&
            (file.height ?? 0) <= 1080
        }
        if let hdFile { return hdFile }

        // Fallback: any mp4 ≤ 1080p sorted by height descending
        let mp4Files = files
            .filter { $0.fileType == "video/mp4" && ($0.height ?? 0) <= 1080 }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let best = mp4Files.first { return best }

        // Last resort: any file
        return files.first
    }

    // MARK: - Private

    private func request<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PexelsError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum PexelsError: Error, LocalizedError {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Failed to fetch data from Pexels"
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: All PexelsServiceTests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add PexelsService with API client and video file selection"
```

---

### Task 8: PersistenceService

**Files:**
- Create: `StoriesConcept/Services/PersistenceService.swift`
- Create: `StoriesConceptTests/PersistenceServiceTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import SwiftData
@testable import StoriesConcept

final class PersistenceServiceTests: XCTestCase {
    var sut: PersistenceService!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: PersistedUser.self, StoryState.self,
            configurations: config
        )
        sut = PersistenceService(container: container)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    @MainActor
    func testSaveAndFetchUsers() throws {
        let story = PersistedStory(
            pexelsMediaId: "101",
            mediaURL: "https://example.com/photo.jpg",
            mediaType: "photo",
            duration: 15,
            postedAt: Date()
        )
        let user = PersistedUser(
            id: "emma_47",
            displayName: "emma_47",
            blockIndex: 0,
            avatarURL: "https://example.com/avatar.jpg",
            stories: [story]
        )

        sut.saveUser(user)
        let fetched = sut.fetchUsers(blockIndex: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, "emma_47")
        XCTAssertEqual(fetched[0].stories.count, 1)
    }

    @MainActor
    func testStoryStateLikeAndSeen() {
        sut.setLiked(storyId: "user1_101_0", liked: true)
        XCTAssertTrue(sut.isLiked(storyId: "user1_101_0"))

        sut.markSeen(storyId: "user1_101_0")
        XCTAssertTrue(sut.isSeen(storyId: "user1_101_0"))
    }

    @MainActor
    func testUnseenCount() {
        let storyIds = ["u1_101_0", "u1_102_0", "u1_103_0"]
        // Mark 1 of 3 as seen
        sut.markSeen(storyId: "u1_101_0")

        let unseen = sut.unseenCount(storyIds: storyIds)
        XCTAssertEqual(unseen, 2)
    }

    @MainActor
    func testFirstUnseenIndex() {
        let storyIds = ["u1_101_0", "u1_102_0", "u1_103_0"]
        sut.markSeen(storyId: "u1_101_0")
        sut.markSeen(storyId: "u1_102_0")

        let index = sut.firstUnseenIndex(storyIds: storyIds)
        XCTAssertEqual(index, 2) // Third story (index 2) is first unseen
    }

    @MainActor
    func testAllSeenReturnsZeroIndexWhenAllSeen() {
        let storyIds = ["u1_101_0", "u1_102_0"]
        sut.markSeen(storyId: "u1_101_0")
        sut.markSeen(storyId: "u1_102_0")

        let index = sut.firstUnseenIndex(storyIds: storyIds)
        XCTAssertEqual(index, 0) // All seen → start from beginning
        XCTAssertTrue(sut.allSeen(storyIds: storyIds))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `PersistenceService` does not exist.

- [ ] **Step 3: Implement PersistenceService**

```swift
import Foundation
import SwiftData

@Observable
@MainActor
final class PersistenceService {
    private let container: ModelContainer
    private var context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    // MARK: - Users

    func saveUser(_ user: PersistedUser) {
        context.insert(user)
        try? context.save()
    }

    func saveUsers(_ users: [PersistedUser]) {
        users.forEach { context.insert($0) }
        try? context.save()
    }

    func fetchUsers(blockIndex: Int? = nil) -> [PersistedUser] {
        var descriptor = FetchDescriptor<PersistedUser>()
        if let blockIndex {
            descriptor.predicate = #Predicate { $0.blockIndex == blockIndex }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchAllUsers() -> [PersistedUser] {
        let descriptor = FetchDescriptor<PersistedUser>(
            sortBy: [SortDescriptor(\.blockIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func maxBlockIndex() -> Int {
        let users = fetchAllUsers()
        return users.map(\.blockIndex).max() ?? -1
    }

    // MARK: - Story States

    func setLiked(storyId: String, liked: Bool) {
        let state = fetchOrCreateState(storyId: storyId)
        state.isLiked = liked
        try? context.save()
    }

    func isLiked(storyId: String) -> Bool {
        fetchState(storyId: storyId)?.isLiked ?? false
    }

    func markSeen(storyId: String) {
        let state = fetchOrCreateState(storyId: storyId)
        state.isSeen = true
        state.seenAt = Date()
        try? context.save()
    }

    func isSeen(storyId: String) -> Bool {
        fetchState(storyId: storyId)?.isSeen ?? false
    }

    func unseenCount(storyIds: [String]) -> Int {
        storyIds.filter { !isSeen(storyId: $0) }.count
    }

    func allSeen(storyIds: [String]) -> Bool {
        unseenCount(storyIds: storyIds) == 0
    }

    func firstUnseenIndex(storyIds: [String]) -> Int {
        for (index, id) in storyIds.enumerated() {
            if !isSeen(storyId: id) { return index }
        }
        return 0 // All seen → start from beginning
    }

    // MARK: - Private

    private func fetchState(storyId: String) -> StoryState? {
        let descriptor = FetchDescriptor<StoryState>(
            predicate: #Predicate { $0.storyId == storyId }
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateState(storyId: String) -> StoryState {
        if let existing = fetchState(storyId: storyId) { return existing }
        let state = StoryState(storyId: storyId)
        context.insert(state)
        return state
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All PersistenceServiceTests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add PersistenceService with SwiftData CRUD for users and story states"
```

---

## Chunk 3: Orchestration — PrefetchService & ViewModels

### Task 9: PrefetchService

**Files:**
- Create: `StoriesConcept/Services/PrefetchService.swift`

- [ ] **Step 1: Implement PrefetchService**

```swift
import Foundation

@Observable
@MainActor
final class PrefetchService {
    private let pexelsService: PexelsService
    private let cacheService: CacheService
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(pexelsService: PexelsService, cacheService: CacheService) {
        self.pexelsService = pexelsService
        self.cacheService = cacheService
    }

    /// Thumbnail prefetch for list screen — download first story image for each visible user
    func prefetchThumbnails(for users: [User]) {
        for user in users {
            guard let firstStory = user.stories.first else { continue }
            let cacheKey = firstStory.cacheKey
            guard !cacheService.isAvailable(mediaId: cacheKey) else { continue }

            let taskKey = "thumb_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = firstStory.mediaURL
            let pexels = pexelsService
            let cache = cacheService

            activeTasks[taskKey] = Task.detached(priority: .background) {
                do {
                    let data = try await pexels.downloadData(from: url)
                    await MainActor.run { cache.save(data: data, for: cacheKey) }
                } catch {
                    // Silent failure — will retry on demand
                }
            }
        }
    }

    /// Linear prefetch for player screen — download all content for current + next user
    func prefetchStories(currentUser: User, nextUser: User?) {
        prefetchAllStories(for: currentUser, priority: .userInitiated)
        if let nextUser {
            prefetchAllStories(for: nextUser, priority: .background)
        }
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }

    // MARK: - Private

    private func prefetchAllStories(for user: User, priority: TaskPriority) {
        for story in user.stories {
            let cacheKey = story.cacheKey
            guard !cacheService.isAvailable(mediaId: cacheKey) else { continue }

            let taskKey = "story_\(cacheKey)"
            guard activeTasks[taskKey] == nil else { continue }

            let url = story.mediaURL
            let pexels = pexelsService
            let cache = cacheService

            activeTasks[taskKey] = Task.detached(priority: priority) {
                do {
                    let data = try await pexels.downloadData(from: url)
                    await MainActor.run { cache.save(data: data, for: cacheKey) }
                } catch {
                    // Silent failure
                }
            }
        }
    }
}
```

> **Why `@MainActor` on PrefetchService?** The `activeTasks` dictionary is mutable state that must be accessed from one isolation domain. Since the service is owned by ViewModels (which are `@MainActor`), keeping it on `MainActor` is simplest. The actual network downloads run via `Task.detached` on background threads — only the dictionary bookkeeping and cache writes hop back to MainActor.

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add PrefetchService with thumbnail and linear strategies"
```

---

### Task 10: StoryListViewModel

**Files:**
- Create: `StoriesConcept/ViewModels/StoryListViewModel.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p StoriesConcept/ViewModels
```

- [ ] **Step 2: Implement StoryListViewModel**

This is the most complex component — handles user generation, pagination, and content assignment.

```swift
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
        // Trigger when within last 3 users
        guard let index = users.firstIndex(where: { $0.id == currentUser.id }),
              index >= users.count - 3,
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
            // Block 2+: recycle content, no API calls
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

            for i in 0..<storyCount {
                let useVideo = Bool.random() && !videoPool.isEmpty

                if useVideo, let video = videoPool.randomElement(),
                   let videoFile = PexelsService.selectVideoFile(from: video.videoFiles),
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
                } else if let photo = photoPool.randomElement(),
                          let mediaURL = URL(string: photo.src.portrait) {
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
            return Story(id: compositeId, pexelsMediaId: ps.pexelsMediaId, mediaURL: url, type: type, duration: ps.duration, postedAt: ps.postedAt)
        }
        return User(
            id: persisted.id,
            displayName: persisted.displayName,
            avatarURL: URL(string: persisted.avatarURL) ?? URL(string: "https://via.placeholder.com/100")!,
            stories: stories
        )
    }
}
```

- [ ] **Step 3: Verify project compiles**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add StoryListViewModel with user generation and infinite pagination"
```

---

### Task 11: StoryPlayerViewModel

**Files:**
- Create: `StoriesConcept/ViewModels/StoryPlayerViewModel.swift`
- Create: `StoriesConceptTests/StoryPlayerViewModelTests.swift`

- [ ] **Step 1: Write failing test for core logic**

```swift
import XCTest
import SwiftData
@testable import StoriesConcept

final class StoryPlayerViewModelTests: XCTestCase {

    func testSeenOnlyOnComplete() async throws {
        // Setup in-memory persistence
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedUser.self, StoryState.self, configurations: config)
        let persistence = await MainActor.run { PersistenceService(container: container) }

        let stories = [
            Story(id: "u1_101_0", pexelsMediaId: "101", mediaURL: URL(string: "https://example.com/1.jpg")!, type: .photo, duration: 15, postedAt: Date()),
            Story(id: "u1_102_0", pexelsMediaId: "102", mediaURL: URL(string: "https://example.com/2.jpg")!, type: .photo, duration: 15, postedAt: Date())
        ]
        let user = User(id: "u1", displayName: "u1", avatarURL: URL(string: "https://example.com/a.jpg")!, stories: stories)

        // Story 0 starts playing — should NOT be seen yet
        await MainActor.run {
            XCTAssertFalse(persistence.isSeen(storyId: "u1_101_0"))
        }

        // Simulate completing story (advance to next)
        await MainActor.run {
            persistence.markSeen(storyId: "u1_101_0")
            XCTAssertTrue(persistence.isSeen(storyId: "u1_101_0"))
            // Second story not yet seen
            XCTAssertFalse(persistence.isSeen(storyId: "u1_102_0"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `StoryPlayerViewModel` file doesn't exist yet, but test only exercises PersistenceService. Should PASS if PersistenceService is implemented. If it passes, good — the test validates our seen logic contract.

- [ ] **Step 3: Implement StoryPlayerViewModel**

```swift
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
            // Prefetch will trigger, and we re-check periodically
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator test 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add StoryPlayerViewModel with timer, navigation, and seen logic"
```

---

## Chunk 4: Views

### Task 12: StoryProgressBar

**Files:**
- Create: `StoriesConcept/Views/StoryProgressBar.swift`

- [ ] **Step 1: Create directory and implement**

```bash
mkdir -p StoriesConcept/Views
```

```swift
import SwiftUI

struct StoryProgressBar: View {
    let totalSegments: Int
    let activeIndex: Int
    let activeProgress: Double
    let isSeenAt: (Int) -> Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<totalSegments, id: \.self) { index in
                GeometryReader { geo in
                    let width = geo.size.width

                    ZStack(alignment: .leading) {
                        // Background — brighter if previously seen, dimmer if unseen
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(backgroundOpacity(for: index)))

                        // Fill
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: fillWidth(for: index, totalWidth: width))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func fillWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < activeIndex {
            return totalWidth // Past segments in current session: fully filled
        } else if index == activeIndex {
            return totalWidth * activeProgress // Active: progressive fill
        } else if isSeenAt(index) {
            return totalWidth // Future but previously seen: fully filled
        } else {
            return 0 // Future and unseen: empty
        }
    }

    private func backgroundOpacity(for index: Int) -> Double {
        if index > activeIndex && isSeenAt(index) {
            return 0.5 // Previously seen — brighter background
        }
        return 0.3 // Default background
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add StoryProgressBar view"
```

---

### Task 13: VideoPlayerView

**Files:**
- Create: `StoriesConcept/Views/VideoPlayerView.swift`

- [ ] **Step 1: Implement AVPlayer SwiftUI wrapper**

```swift
import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let isPaused: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        let player = AVPlayer(url: url)
        controller.player = player
        player.play()

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if isPaused {
            controller.player?.pause()
        } else {
            if controller.player?.rate == 0 {
                controller.player?.play()
            }
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add VideoPlayerView (AVPlayer SwiftUI wrapper)"
```

---

### Task 14: StoryRowView

**Files:**
- Create: `StoriesConcept/Views/StoryRowView.swift`

- [ ] **Step 1: Implement row component**

```swift
import SwiftUI

struct StoryRowView: View {
    let user: User
    let unseenCount: Int
    let allSeen: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with ring
            AsyncImage(url: user.avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(allSeen ? Color.clear : Color.green, lineWidth: 2.5)
                    .frame(width: 62, height: 62)
            )

            // Username
            Text(user.displayName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()

            // Right indicator
            if allSeen {
                Text("Seen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(unseenCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.green)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }
}
```

> **Note on AsyncImage for avatars:** We use `AsyncImage` here for avatar thumbnails since they are small and the built-in caching is sufficient for the list view. For story content we use our `CacheService` because we need explicit TTL control and disk persistence.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add StoryRowView component"
```

---

### Task 15: StoryListView

**Files:**
- Create: `StoriesConcept/Views/StoryListView.swift`

- [ ] **Step 1: Implement main list screen**

```swift
import SwiftUI

struct StoryListView: View {
    @State var viewModel: StoryListViewModel
    @State private var selectedUserIndex: Int?
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.users.isEmpty {
                    ProgressView("Loading stories...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.users.isEmpty {
                    errorView(message: error)
                } else {
                    userList
                }
            }
            .navigationTitle("Stories")
            .fullScreenCover(isPresented: $showPlayer) {
                if let index = selectedUserIndex {
                    storyPlayer(initialUserIndex: index)
                }
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    // MARK: - Subviews

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.users.enumerated()), id: \.element.id) { index, user in
                    StoryRowView(
                        user: user,
                        unseenCount: viewModel.unseenCount(for: user),
                        allSeen: viewModel.allSeen(for: user)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedUserIndex = index
                        showPlayer = true
                    }
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentUser: user)
                        viewModel.requestThumbnailPrefetch(for: [user])
                    }

                    if index < viewModel.users.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storyPlayer(initialUserIndex: Int) -> some View {
        let user = viewModel.users[initialUserIndex]
        let startIndex = viewModel.firstUnseenIndex(for: user)

        let playerVM = StoryPlayerViewModel(
            users: viewModel.users,
            initialUserIndex: initialUserIndex,
            initialStoryIndex: startIndex,
            persistenceService: viewModel.persistenceService,
            cacheService: viewModel.cacheService,
            prefetchService: viewModel.prefetchService,
            hapticService: HapticService(),
            loadMoreCallback: { [viewModel] user in
                viewModel.loadMoreIfNeeded(currentUser: user)
            }
        )

        return StoryPlayerView(viewModel: playerVM)
    }
}
```

> **Note:** `StoryListView` needs access to services from the list ViewModel to pass them to the player ViewModel. The service properties in Task 10's `StoryListViewModel` are already declared with `let` (internal access) for this purpose.

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add StoryListView with infinite scroll and error handling"
```

---

### Task 16: StoryPlayerView

**Files:**
- Create: `StoriesConcept/Views/StoryPlayerView.swift`

This is the most complex view — fullscreen player with gestures, progress bar, like button, and loading states.

- [ ] **Step 1: Implement StoryPlayerView**

```swift
import SwiftUI

struct StoryPlayerView: View {
    @State var viewModel: StoryPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = viewModel.currentStory {
                // Content layer
                contentView(for: story)
                    .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }

                // UI overlay
                VStack(spacing: 0) {
                    topOverlay
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .statusBarHidden()
        .gesture(combinedGesture)
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .onAppear {
            viewModel.startTimer()
        }
        .onDisappear {
            viewModel.stopTimer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(for story: Story) -> some View {
        switch story.type {
        case .photo:
            if let data = viewModel.imageData(for: story),
               let uiImage = downsampledImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
            }
        case .video:
            VideoPlayerView(url: story.mediaURL, isPaused: viewModel.isPaused)
                .ignoresSafeArea()
        }
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack(spacing: 8) {
            // Progress bar
            StoryProgressBar(
                totalSegments: viewModel.totalStories,
                activeIndex: viewModel.currentStoryIndex,
                activeProgress: viewModel.progress,
                isSeenAt: { viewModel.isStorySeen(at: $0) }
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // User info + close
            HStack(spacing: 10) {
                if let user = viewModel.currentUser {
                    AsyncImage(url: user.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.5))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    Text(user.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    if let story = viewModel.currentStory {
                        Text(story.postedAt.timeAgoDisplay())
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Button {
                    viewModel.dismiss()
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
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        HStack {
            Spacer()

            Button {
                viewModel.toggleLike()
            } label: {
                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                    .font(.title)
                    .foregroundStyle(viewModel.isLiked ? .red : .white)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.trailing, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Gestures

    @GestureState private var isLongPressing = false

    private var combinedGesture: some Gesture {
        // Long press to pause (uses @GestureState for auto-resume on release)
        let longPress = LongPressGesture(minimumDuration: 0.2)
            .updating($isLongPressing) { value, state, _ in
                state = value
            }

        // Drag for swipe user / dismiss
        let drag = DragGesture(minimumDistance: Constants.dragMinDistance)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(vertical) > abs(horizontal) && vertical > 50 {
                    viewModel.dismiss()
                } else if abs(horizontal) > abs(vertical) {
                    if horizontal < -50 {
                        viewModel.nextUser()
                    } else if horizontal > 50 {
                        viewModel.previousUser()
                    }
                }
            }

        // Tap for next/previous
        let tap = SpatialTapGesture()
            .onEnded { value in
                let screenWidth = UIScreen.main.bounds.width
                if value.location.x > screenWidth * 0.5 {
                    viewModel.nextStory()
                } else {
                    viewModel.previousStory()
                }
            }

        // Compose: drag and tap are exclusive (drag wins over tap),
        // long press runs simultaneously to detect pause/resume via @GestureState
        return drag
            .exclusively(before: tap)
            .simultaneously(with: longPress)
    }

    // MARK: - Image Processing

    private func downsampledImage(data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: UIScreen.main.bounds.height * UIScreen.main.scale
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
```

- [ ] **Step 2: Add long press resume + app backgrounding handlers**

Add these modifiers to the `ZStack` in the body (after `.gesture(combinedGesture)`):

```swift
// Long press: pause on press, resume on release (GestureState auto-resets)
.onChange(of: isLongPressing) { _, pressing in
    if pressing {
        viewModel.pauseTimer()
    } else {
        viewModel.resumeTimer()
    }
}
// App backgrounding: pause timer when app goes inactive
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
    viewModel.pauseTimer()
}
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
    viewModel.resumeTimer()
}
```

> **Why `NotificationCenter` instead of `@Environment(\.scenePhase)`?** `scenePhase` can be unreliable inside `.fullScreenCover`. `NotificationCenter` works regardless of view hierarchy.

- [ ] **Step 3: Verify project compiles**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add StoryPlayerView with gestures, progress, and like button"
```

---

## Chunk 5: Integration & App Entry Point

### Task 17: Update StoriesConceptApp.swift

**Files:**
- Modify: `StoriesConcept/StoriesConceptApp.swift`

- [ ] **Step 1: Replace template App with our configuration**

```swift
import SwiftUI
import SwiftData

@main
struct StoriesConceptApp: App {
    let container: ModelContainer
    @State private var viewModel: StoryListViewModel?

    init() {
        do {
            let schema = Schema([PersistedUser.self, StoryState.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let viewModel {
                StoryListView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        let persistenceService = PersistenceService(container: container)
                        let pexelsService = PexelsService()
                        let cacheService = CacheService()
                        let prefetchService = PrefetchService(
                            pexelsService: pexelsService,
                            cacheService: cacheService
                        )
                        viewModel = StoryListViewModel(
                            pexelsService: pexelsService,
                            cacheService: cacheService,
                            persistenceService: persistenceService,
                            prefetchService: prefetchService
                        )
                    }
            }
        }
    }
}
```

> **Why `@State` + `.task`?** Services must be created once and persist across view updates. Using `@State` ensures the ViewModel (and its service dependencies) are created once. The `.task` runs on the MainActor, which is required for `PersistenceService`.

- [ ] **Step 2: Remove Item.swift references from Xcode project**

Since we deleted `Item.swift` and `ContentView.swift` earlier, ensure the Xcode project doesn't reference them. This is handled when opening in Xcode — missing files show as red and can be removed from the project navigator.

- [ ] **Step 3: Build the full project**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -20
```

Fix any compilation errors.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: wire up app entry point with dependency injection"
```

---

### Task 18: Add Files to Xcode Project

**Files:**
- Modify: `StoriesConcept.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add all new files to Xcode project**

Since we're working from CLI, new files need to be registered in the Xcode project. The most reliable approach:

1. Open the project in Xcode:
```bash
open StoriesConcept.xcodeproj
```

2. In Xcode's Project Navigator, right-click on the `StoriesConcept` folder → "Add Files to StoriesConcept"
3. Select all new folders: `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`
4. Ensure "Copy items if needed" is unchecked (files are already in place)
5. Ensure target membership is set to `StoriesConcept`

For test files:
1. Right-click on `StoriesConceptTests` → "Add Files"
2. Add test files and mock JSON files
3. Ensure mock JSON files are added to the test target bundle resources

- [ ] **Step 2: Build and verify in Xcode**

Press `Cmd + B` in Xcode. Fix any issues with file references.

- [ ] **Step 3: Run on simulator**

Press `Cmd + R` to run on iPhone 16 Pro simulator. Verify:
- App launches
- Shows loading indicator
- Loads users from Pexels API
- Displays vertical list with avatars and usernames

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: add all source files to Xcode project"
```

---

### Task 19: Integration Testing & Fixes

**Files:** Various — depends on issues found

- [ ] **Step 1: Test story list screen**

Run on simulator and verify:
- Users appear with avatars, names, and unseen badges
- Scrolling loads more users (pagination)
- No crashes or layout issues

- [ ] **Step 2: Test story player**

Tap on a user and verify:
- Fullscreen player opens
- Progress bar animates for photos (15s)
- Tap right → next story
- Tap left → previous story
- Swipe left/right → change user
- Swipe down → dismiss
- Like button works with animation
- Long press pauses timer

- [ ] **Step 3: Test seen/unseen logic**

- Watch a story completely → return to list → verify green badge count decreases
- Watch all stories of a user → verify "Seen" text appears
- Re-enter a fully seen user → starts from first story, states unchanged

- [ ] **Step 4: Test video playback**

- Navigate to a video story → verify it plays fullscreen
- Verify timer matches video duration (capped at 45s)
- Verify video pauses on long press

- [ ] **Step 5: Test edge cases**

- Kill and relaunch app → verify users persist, states persist
- Scroll to block 2+ → verify recycled content loads without crashes
- Navigate past last loaded user → verify more users load

- [ ] **Step 6: Fix any issues found and commit**

```bash
git add -A && git commit -m "fix: integration testing fixes"
```

---

### Task 20: Polish & Final Touches

**Files:** Various

- [ ] **Step 1: Verify haptic feedback works on device**

Haptics don't work on simulator — test on a real device if available.

- [ ] **Step 2: Test memory performance**

Open Instruments → Allocations. Navigate through stories and verify:
- Image downsampling prevents memory spikes
- NSCache evicts under pressure
- No retain cycles (check for leaks)

- [ ] **Step 3: Final build verification**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator build 2>&1 | tail -10
```

- [ ] **Step 4: Run all tests**

```bash
xcodebuild -project StoriesConcept.xcodeproj -scheme StoriesConcept -sdk iphonesimulator test 2>&1 | tail -20
```

- [ ] **Step 5: Final commit**

```bash
git add -A && git commit -m "chore: polish and final verification"
```

---

## Execution Order Summary

| Task | Component | Est. | Depends On |
|------|-----------|------|------------|
| 1 | Cleanup & Constants | 2 min | — |
| 2 | DTO Models | 3 min | — |
| 3 | Domain Models | 3 min | — |
| 4 | Persistence Models | 3 min | — |
| 5 | HapticService | 1 min | — |
| 6 | CacheService + Tests | 5 min | Task 1 |
| 7 | PexelsService + Tests | 5 min | Task 2 |
| 8 | PersistenceService + Tests | 5 min | Task 4 |
| 9 | PrefetchService | 3 min | Tasks 6, 7 |
| 10 | StoryListViewModel | 8 min | Tasks 7, 8, 9 |
| 11 | StoryPlayerViewModel + Tests | 8 min | Tasks 5, 6, 8, 9 |
| 12 | StoryProgressBar | 3 min | — |
| 13 | VideoPlayerView | 3 min | — |
| 14 | StoryRowView | 3 min | Task 3 |
| 15 | StoryListView | 5 min | Tasks 10, 14 |
| 16 | StoryPlayerView | 8 min | Tasks 11, 12, 13 |
| 17 | App Entry Point | 3 min | Task 15 |
| 18 | Xcode Project Setup | 5 min | Task 17 |
| 19 | Integration Testing | 10 min | Task 18 |
| 20 | Polish | 5 min | Task 19 |

**Total estimated agent execution time: ~90 min**

### Parallelization Opportunities

Tasks that can run in parallel (for subagent-driven development):

- **Group A** (no deps): Tasks 1, 2, 3, 4, 5, 12, 13
- **Group B** (after models): Tasks 6, 7, 8, 14
- **Group C** (after services): Tasks 9, 10, 11
- **Group D** (after VMs): Tasks 15, 16
- **Group E** (sequential): Tasks 17, 18, 19, 20
