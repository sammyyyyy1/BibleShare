import SwiftUI

struct TimelineView: View {
    let userID: UUID

    @State private var vm = TimelineViewModel()
    @State private var commentingOn: FeedItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let error = vm.errorMessage {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                        Spacer()
                        Button("Retry") { Task { await vm.load(userID: userID) } }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                }

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView().tint(Theme.indigo).padding(.top, 40)
                } else if vm.items.isEmpty && vm.errorMessage == nil {
                    emptyState
                }

                ForEach(vm.items) { item in
                    PostCell(
                        item: item,
                        isMine: item.authorID == userID,
                        onLike: { Task { await vm.toggleLike(itemID: item.id, userID: userID) } },
                        onComment: { commentingOn = item },
                        onDelete: { Task { await vm.delete(itemID: item.id) } }
                    )
                    .onAppear {
                        if item.id == vm.items.last?.id {
                            Task { await vm.loadMore(userID: userID) }
                        }
                    }
                }

                if vm.isLoadingMore {
                    ProgressView().tint(Theme.indigo).padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.cream)
        .refreshable { await vm.load(userID: userID) }
        .task { await vm.load(userID: userID) }
        .sheet(item: $commentingOn) { item in
            CommentsView(postID: item.id, userID: userID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20).fill(Theme.hairline.opacity(0.6))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "bird").font(.system(size: 28)).foregroundStyle(Theme.indigo))
            Text("No encouragements yet")
                .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
            Text("Share something that lifted you up today.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}
