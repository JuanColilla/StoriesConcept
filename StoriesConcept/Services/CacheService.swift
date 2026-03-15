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
