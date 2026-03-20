import ComposableArchitecture
import Foundation
import os

struct AppFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var storyList = StoryListFeature.State()
    }

    @CasePathable
    enum Action {
        case storyList(StoryListFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.storyList, action: \.storyList) {
            StoryListFeature()
        }
    }
}
