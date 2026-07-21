import Foundation

@MainActor
@Observable
final class TimelineViewModel: FeedLikeHandling {
    static let pageSize = 20

    // Settable (not private(set)) so the FeedLikeHandling mixin can mutate it.
    var items: [FeedItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    private let feed: FeedServicing
    private let posts: PostServicing

    var likeFeed: FeedServicing { feed }
    var likePosts: PostServicing { posts }

    init(feed: FeedServicing = FeedService.shared,
         posts: PostServicing = PostService.shared) {
        self.feed = feed
        self.posts = posts
    }

    func load(userID: UUID) async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await feed.fetchTimeline(before: nil, limit: Self.pageSize)
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
            let page = try await feed.fetchTimeline(before: cursor, limit: Self.pageSize)
            items += try await markLiked(page, userID: userID)
            hasMore = page.count == Self.pageSize
        } catch {
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
