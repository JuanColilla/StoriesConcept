import ComposableArchitecture
import os
import SwiftUI
import SwiftData

@main
struct StoriesConceptApp: App {
    let store: StoreOf<AppFeature>

    init() {
        let container = Self.createContainer()

        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient = .live(container: container)
        }
    }

    private static func createContainer() -> ModelContainer {
        let schema = Schema([PersistedUser.self, StoryState.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        destroyStoreIfNeeded(url: config.url)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Destroys the SwiftData store once after the TCA migration.
    /// Uses the real URL from ModelConfiguration — no guessing.
    private static func destroyStoreIfNeeded(url: URL?) {
        let key = "didMigrateToTCA_v1"
        // TODO: Remove after first successful migration test
        UserDefaults.standard.removeObject(forKey: key)
        guard !UserDefaults.standard.bool(forKey: key), let url else { return }

        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: file.path) {
                try? fm.removeItem(at: file)
                Logger.persist.info("Removed: \(file.lastPathComponent, privacy: .public)")
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        Logger.persist.info("Migration complete: destroyed pre-TCA SwiftData store")
    }

    var body: some Scene {
        WindowGroup {
            StoryListView(
                store: store.scope(state: \.storyList, action: \.storyList)
            )
        }
    }
}
