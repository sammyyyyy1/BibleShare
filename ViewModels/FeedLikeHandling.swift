import Foundation

/// Shared optimistic like-handling for feed-style ViewModels (the Home timeline
/// and group timelines). Both hold a `[FeedItem]` list and toggle likes
/// identically; this mixin is the single source of that logic. `userID` is
/// passed per call so conformers needn't store it (TimelineViewModel receives it
/// per call; GroupTimelineViewModel passes its stored `myID`).
@MainActor
protocol FeedLikeHandling: AnyObject {
    var items: [FeedItem] { get set }
    var errorMessage: String? { get set }
    var likeFeed: FeedServicing { get }
    var likePosts: PostServicing { get }
}

extension FeedLikeHandling {
    /// `likes(count)` gives the tally but not membership, so ask which of these
    /// posts the viewer has liked and stamp `isLiked`.
    func markLiked(_ page: [FeedItem], userID: UUID) async throws -> [FeedItem] {
        guard !page.isEmpty else { return page }
        let liked = try await likeFeed.likedPostIDs(userID: userID, among: page.map(\.id))
        return page.map { item in
            var copy = item
            copy.isLiked = liked.contains(item.id)
            return copy
        }
    }

    /// Optimistically flips the like on `itemID`, calls the service, and reverts
    /// on failure (the row index may shift while awaiting).
    func toggleLike(itemID: UUID, userID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let wasLiked = items[index].isLiked
        let target = !wasLiked
        items[index].isLiked = target
        items[index].likeCount += target ? 1 : -1
        do {
            try await likePosts.setLike(postID: itemID, userID: userID, liked: target)
        } catch {
            if let current = items.firstIndex(where: { $0.id == itemID }) {
                items[current].isLiked = wasLiked
                items[current].likeCount += target ? -1 : 1
            }
            errorMessage = PostError.message(for: error)
        }
    }
}
