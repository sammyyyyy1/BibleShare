import Foundation

@MainActor
@Observable
final class TimelineViewModel {
    static let pageSize = 20

    private(set) var items: [FeedItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    private let feed: FeedServicing
    private let posts: PostServicing

    init(feed: FeedServicing = FeedService.shared,
         posts: PostServicing = PostService.shared) {
        self.feed = feed
        self.posts = posts
    }

    func load(userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await feed.fetchTimeline(authorID: userID, before: nil, limit: Self.pageSize)
            items = try await markLiked(page, userID: userID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore(userID: UUID) async {
        guard hasMore, !isLoading, !isLoadingMore, let cursor = items.last?.createdAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await feed.fetchTimeline(authorID: userID, before: cursor, limit: Self.pageSize)
            items += try await markLiked(page, userID: userID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    /// `likes(count)` gives the tally but not membership, so ask which of these
    /// posts the viewer has liked.
    private func markLiked(_ page: [FeedItem], userID: UUID) async throws -> [FeedItem] {
        guard !page.isEmpty else { return page }
        let liked = try await feed.likedPostIDs(userID: userID, among: page.map(\.id))
        return page.map { item in
            var copy = item
            copy.isLiked = liked.contains(item.id)
            return copy
        }
    }

    func toggleLike(itemID: UUID, userID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let wasLiked = items[index].isLiked
        let target = !wasLiked

        // Optimistic.
        items[index].isLiked = target
        items[index].likeCount += target ? 1 : -1

        do {
            try await posts.setLike(postID: itemID, userID: userID, liked: target)
        } catch {
            // Revert — the row index may have shifted while awaiting.
            if let current = items.firstIndex(where: { $0.id == itemID }) {
                items[current].isLiked = wasLiked
                items[current].likeCount += target ? -1 : 1
            }
            errorMessage = PostError.message(for: error)
        }
    }

    func delete(itemID: UUID) async {
        let imagePaths = items.first(where: { $0.id == itemID })?.images.map(\.url) ?? []
        do {
            try await posts.deletePost(id: itemID, imagePaths: imagePaths)
            items.removeAll { $0.id == itemID }
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func insert(_ item: FeedItem) {
        items.insert(item, at: 0)
    }
}
