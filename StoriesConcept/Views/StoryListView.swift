import SwiftUI

struct StoryListView: View {
    @State var viewModel: StoryListViewModel
    @State private var selectedUserIndex: Int?

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
            .safeAreaInset(edge: .bottom) {
                // Offline banner — visible regardless of cached data
                if !viewModel.networkMonitor.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline)
                        Text("No connection")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.85))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.networkMonitor.isConnected)
                }
            }
            .navigationTitle("Stories")
            .refreshable {
                await viewModel.refresh()
            }
            .fullScreenCover(isPresented: Binding(
                get: { selectedUserIndex != nil },
                set: { if !$0 { selectedUserIndex = nil } }
            )) {
                storyPlayer(initialUserIndex: selectedUserIndex ?? 0)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .onChange(of: viewModel.networkMonitor.isConnected) { _, isConnected in
            guard isConnected else { return }
            // Connectivity restored — retry initial load if it failed,
            // or re-trigger thumbnail prefetch for visible users.
            Task {
                if viewModel.users.isEmpty {
                    await viewModel.retry()
                } else {
                    viewModel.requestThumbnailPrefetch(for: viewModel.users)
                }
            }
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
                    }
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentIndex: index)
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
            // Pink circle background with wifi icon (matching design)
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
                Task { await viewModel.retry() }
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
