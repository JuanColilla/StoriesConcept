//
//  StoriesConceptApp.swift
//  StoriesConcept
//
//  Created by Juan Colilla on 15/3/26.
//

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
