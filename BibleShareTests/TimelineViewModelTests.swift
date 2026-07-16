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
