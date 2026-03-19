import ComposableArchitecture
import Sharing
import SwiftUI

struct StoryListView: View {
    @Bindable var store: StoreOf<StoryListFeature>
    @Shared(.inMemory("seenIds")) var seenIds: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.users.isEmpty {
                    ProgressView("Loading stories...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage, store.users.isEmpty {
                    errorView(message: error)
                } else {
                    userList
                }
            }
            .navigationTitle("Stories")
            .refreshable {
                await store.send(.refresh).finish()
            }
            .fullScreenCover(
                item: $store.scope(state: \.player, action: \.player)
            ) { playerStore in
                StoryPlayerView(store: playerStore)
            }
        }
        .task {
            store.send(.onAppear)
        }
    }

    // MARK: - Subviews

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.users.enumerated()), id: \.element.id) { index, user in
                    let storyIds = user.stories.map(\.id)
                    let unseen = storyIds.filter { !seenIds.contains($0) }.count
                    let allSeen = unseen == 0

                    StoryRowView(
                        user: user,
                        unseenCount: unseen,
                        allSeen: allSeen
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.userTapped(index: index))
                    }
                    .onAppear {
                        store.send(.loadMoreIfNeeded(currentIndex: index))
                        store.send(.prefetchThumbnails(visibleUsers: [user]))
                    }

                    if index < store.users.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
            }

            Text("No connection")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Check your internet connection and try again\nto see the latest stories.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                store.send(.retry)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
