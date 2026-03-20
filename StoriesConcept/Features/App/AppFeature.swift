import ComposableArchitecture
import Foundation
import os

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var storyList = StoryListFeature.State()
    }

    enum Action {
        case storyList(StoryListFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.storyList, action: \.storyList) {
            StoryListFeature()
        }
    }
}
