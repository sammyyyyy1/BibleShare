import Testing
import Foundation
@testable import BibleShare

@MainActor
struct TimelineViewModelTests {

    @Test func loadPopulatesItemsAndMarksLiked() async throws {
        let me = UUID()
        let liked = try FeedItemFactory.make(authorID: me, title: "Liked", likeCount: 2)
        let plain = try FeedItemFactory.make(authorID: me, title: "Plain", likeCount: 0)
        let feed = FakeFeedService()
        feed.pages = [[liked, plain]]
        feed.liked = [liked.id]

        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: me)

        #expect(vm.items.count == 2)
        #expect(vm.items.first(where: { $0.id == liked.id })?.isLiked == true)
        #expect(vm.items.first(where: { $0.id == plain.id })?.isLiked == false)
        #expect(vm.isLoading == false)
    }

    @Test func loadSurfacesErrors() async {
        struct Boom: Error {}
        let feed = FakeFeedService()
        feed.error = Boom()
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    /// A short page means the end of the feed.
    @Test func shortPageClearsHasMore() async throws {
        let feed = FakeFeedService()
        feed.pages = [[try FeedItemFactory.make()]]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        #expect(vm.hasMore == false)
    }

    @Test func toggleLikeUpdatesOptimistically() async throws {
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == true)
        #expect(vm.items[0].likeCount == 3)
        #expect(posts.likeCalls.map(\.liked) == [true])

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == false)
        #expect(vm.items[0].likeCount == 2)
    }

    /// The optimistic update must not survive a server rejection.
    @Test func failedLikeRevertsCountAndFlag() async throws {
        struct Boom: Error {}
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        posts.likeError = Boom()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == false, "the flag must revert")
        #expect(vm.items[0].likeCount == 2, "the count must revert")
        #expect(vm.errorMessage != nil)
    }

    /// A non-optimistic implementation that only mutated `items` after `setLike`
    /// succeeded would satisfy `toggleLikeUpdatesOptimistically` identically. This
    /// test captures state WHILE the "server call" is in flight to prove the UI
    /// really did update before the request resolved.
    @Test func toggleLikeAppliesOptimisticallyBeforeTheServerCall() async throws {
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        var capturedLiked: Bool?
        var capturedCount: Int?
        posts.onSetLike = {
            capturedLiked = vm.items[0].isLiked
            capturedCount = vm.items[0].likeCount
        }

        await vm.toggleLike(itemID: item.id, userID: UUID())

        #expect(capturedLiked == true, "the flag must already be set while the server call is in flight")
        #expect(capturedCount == 3, "the count must already be bumped while the server call is in flight")
    }

    /// Distinguishes a real revert from a no-op: the mid-flight capture must show
    /// the optimistic value applied, while the final state must show it reverted.
    @Test func failedLikeAppliesThenRevertsRatherThanNeverApplying() async throws {
        struct Boom: Error {}
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        posts.likeError = Boom()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        var capturedLiked: Bool?
        var capturedCount: Int?
        posts.onSetLike = {
            capturedLiked = vm.items[0].isLiked
            capturedCount = vm.items[0].likeCount
        }

        await vm.toggleLike(itemID: item.id, userID: UUID())

        #expect(capturedLiked == true, "it must have applied optimistically before failing")
        #expect(capturedCount == 3, "it must have applied optimistically before failing")
        #expect(vm.items[0].isLiked == false, "it must revert after the server rejects it")
        #expect(vm.items[0].likeCount == 2, "it must revert after the server rejects it")
    }

    @Test func loadMoreAppendsAndPassesTheOldestLoadedCreatedAtAsCursor() async throws {
        let now = Date()
        let page1 = try (0..<TimelineViewModel.pageSize).map { i in
            try FeedItemFactory.make(title: "P1-\(i)", createdAt: now.addingTimeInterval(-Double(i) * 60))
        }
        let page2 = try (0..<2).map { i in
            try FeedItemFactory.make(title: "P2-\(i)",
                                     createdAt: now.addingTimeInterval(-Double(TimelineViewModel.pageSize + i) * 60))
        }
        let feed = FakeFeedService()
        feed.pages = [page1, page2]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())

        await vm.load(userID: UUID())
        #expect(vm.hasMore == true, "a full page implies there may be more")
        #expect(vm.items.count == TimelineViewModel.pageSize)

        let oldestLoaded = try #require(vm.items.last?.createdAt)

        await vm.loadMore(userID: UUID())

        #expect(vm.items.count == TimelineViewModel.pageSize + 2)
        #expect(vm.items.suffix(2).map(\.title) == ["P2-0", "P2-1"], "the new page must be appended, not prepended")
        #expect(feed.receivedCursors == [nil, oldestLoaded],
                "the cursor must be the oldest loaded row's createdAt, not the newest")
        #expect(vm.hasMore == false, "a short page means the end of the feed")
    }

    @Test func loadMoreDoesNothingWhenNoMorePages() async throws {
        let feed = FakeFeedService()
        feed.pages = [[try FeedItemFactory.make()]]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())
        #expect(vm.hasMore == false)

        await vm.loadMore(userID: UUID())
        #expect(feed.receivedCursors.count == 1, "the guard must hold and no second fetch must happen")
    }

    @Test func deleteRemovesItem() async throws {
        let item = try FeedItemFactory.make()
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.delete(itemID: item.id)
        #expect(vm.items.isEmpty)
        #expect(posts.deletedPosts == [item.id])
    }

    /// The item must be removed ONLY after the server call succeeds.
    @Test func failedDeleteKeepsItem() async throws {
        struct Boom: Error {}
        let item = try FeedItemFactory.make()
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        posts.deleteError = Boom()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.delete(itemID: item.id)
        #expect(vm.items.map(\.id) == [item.id], "the item must survive a failed delete")
        #expect(vm.errorMessage != nil)
    }

    @Test func insertPutsNewPostOnTop() async throws {
        let existing = try FeedItemFactory.make(title: "Old")
        let feed = FakeFeedService()
        feed.pages = [[existing]]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        vm.insert(try FeedItemFactory.make(title: "New"))
        #expect(vm.items.map(\.title) == ["New", "Old"])
    }
}
