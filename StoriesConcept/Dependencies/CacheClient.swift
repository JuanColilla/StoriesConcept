import ComposableArchitecture
import Foundation
import os

@DependencyClient
struct CacheClient: Sendable {
    var save: @Sendable (_ data: Data, _ mediaId: String, _ ttl: TimeInterval) async -> Void
    var load: @Sendable (_ mediaId: String) async -> Data?
    var isAvailable: @Sendable (_ mediaId: String) -> Bool = { _ in false }
    var clearAll: @Sendable () async -> Void
}

extension CacheClient: DependencyKey {
    static let liveValue: CacheClient = {
        // Use an actor to make the cache thread-safe
        let cache = CacheActor()
        return CacheClient(
            save: { data, mediaId, ttl in
                await cache.save(data: data, for: mediaId, ttl: ttl)
            },
            load: { mediaId in
                await cache.load(mediaId: mediaId)
            },
            isAvailable: { mediaId in
                // Synchronous check — memory cache or disk file exists
                // This needs a non-async path for reducer synchronous checks
                FileManager.default.fileExists(
                    atPath: CacheActor.cacheDirectory.appendingPathComponent(mediaId).path
                )
            },
            clearAll: {
                await cache.clearAll()
            }
        )
    }()

    static let previewValue = CacheClient(
        save: { _, _, _ in },
        load: { _ in nil },
        isAvailable: { _ in true },
        clearAll: {}
    )
}

extension DependencyValues {
    var cacheClient: CacheClient {
        get { self[CacheClient.self] }
        set { self[CacheClient.self] = newValue }
    }
}

// MARK: - Cache Actor (thread-safe implementation)

private actor CacheActor {
    static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("StoryCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var metadata: [String: Date] = [:]
    private let memoryCache = NSCache<NSString, NSData>()

    init() {
        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 100 * 1024 * 1024
        loadMetadata()
    }

    func save(data: Data, for mediaId: String, ttl: TimeInterval) {
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
        let fileURL = Self.cacheDirectory.appendingPathComponent(mediaId)
        try? data.write(to: fileURL)
        metadata[mediaId] = Date().addingTimeInterval(ttl)
        saveMetadata()
        Logger.cache.debug("Saved \(mediaId, privacy: .public) (\(data.count) bytes)")
    }

    func load(mediaId: String) -> Data? {
        if let expiresAt = metadata[mediaId], Date() > expiresAt {
            remove(mediaId: mediaId)
            return nil
        }
        if let cached = memoryCache.object(forKey: mediaId as NSString) {
            return cached as Data
        }
        let fileURL = Self.cacheDirectory.appendingPathComponent(mediaId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
        return data
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        metadata.removeAll()
        Logger.cache.info("Cache cleared")
    }

    private func remove(mediaId: String) {
        memoryCache.removeObject(forKey: mediaId as NSString)
        let fileURL = Self.cacheDirectory.appendingPathComponent(mediaId)
        try? FileManager.default.removeItem(at: fileURL)
        metadata.removeValue(forKey: mediaId)
        saveMetadata()
    }

    private var metadataFile: URL {
        Self.cacheDirectory.appendingPathComponent("cache_metadata.plist")
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
