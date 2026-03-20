import ComposableArchitecture
import Foundation
import os

struct CacheClient: Sendable {
    var save: @Sendable (_ data: Data, _ mediaId: String, _ ttl: TimeInterval) async -> Void
    var load: @Sendable (_ mediaId: String) async -> Data?
    var isAvailable: @Sendable (_ mediaId: String) -> Bool
    var clearAll: @Sendable () async -> Void
}

extension CacheClient: DependencyKey {
    static let liveValue: CacheClient = {
        let cache = CacheStorage()
        return CacheClient(
            save: { data, mediaId, ttl in
                cache.save(data: data, for: mediaId, ttl: ttl)
            },
            load: { mediaId in
                cache.load(mediaId: mediaId)
            },
            isAvailable: { mediaId in
                cache.isAvailable(mediaId: mediaId)
            },
            clearAll: {
                cache.clearAll()
            }
        )
    }()

    static let testValue = CacheClient(
        save: { _, _, _ in },
        load: { _ in nil },
        isAvailable: { _ in false },
        clearAll: { }
    )

    static let previewValue = CacheClient(
        save: { _, _, _ in },
        load: { _ in nil },
        isAvailable: { _ in true },
        clearAll: { }
    )
}

extension DependencyValues {
    var cacheClient: CacheClient {
        get { self[CacheClient.self] }
        set { self[CacheClient.self] = newValue }
    }
}

// MARK: - Thread-safe storage (NOT an actor — uses NSLock for sync access)

private final class CacheStorage: @unchecked Sendable {
    private let memoryCache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var metadata: [String: Date] = [:]

    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("StoryCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 100 * 1024 * 1024
        loadMetadata()
    }

    func save(data: Data, for mediaId: String, ttl: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        try? data.write(to: fileURL)
        metadata[mediaId] = Date().addingTimeInterval(ttl)
        saveMetadata()
    }

    func load(mediaId: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let expiresAt = metadata[mediaId], Date() > expiresAt {
            removeUnlocked(mediaId: mediaId)
            return nil
        }
        if let cached = memoryCache.object(forKey: mediaId as NSString) {
            return cached as Data
        }
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
        return data
    }

    func isAvailable(mediaId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let expiresAt = metadata[mediaId], Date() > expiresAt {
            return false
        }
        if memoryCache.object(forKey: mediaId as NSString) != nil { return true }
        return FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(mediaId).path)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        metadata.removeAll()
    }

    private func removeUnlocked(mediaId: String) {
        memoryCache.removeObject(forKey: mediaId as NSString)
        let fileURL = cacheDirectory.appendingPathComponent(mediaId)
        try? FileManager.default.removeItem(at: fileURL)
        metadata.removeValue(forKey: mediaId)
        saveMetadata()
    }

    private func loadMetadata() {
        let file = cacheDirectory.appendingPathComponent("cache_metadata.plist")
        guard let data = try? Data(contentsOf: file),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        metadata = dict
    }

    private func saveMetadata() {
        let file = cacheDirectory.appendingPathComponent("cache_metadata.plist")
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: file)
    }
}
