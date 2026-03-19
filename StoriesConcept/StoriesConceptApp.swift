import ComposableArchitecture
import SwiftUI
import SwiftData

@main
struct StoriesConceptApp: App {
    let store: StoreOf<AppFeature>

    init() {
        let container: ModelContainer
        do {
            let schema = Schema([PersistedUser.self, StoryState.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient = .live(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            StoryListView(
                store: store.scope(state: \.storyList, action: \.storyList)
            )
        }
    }
}
