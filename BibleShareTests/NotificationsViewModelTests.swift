import Testing
import Foundation
@testable import BibleShare

@MainActor
struct NotificationsViewModelTests {
    private func unreadItem() -> NotificationItem {
        let json = """
        {"id":"\(UUID().uuidString)","recipient_id":"\(UUID().uuidString)",
         "type":"post_like","actor_id":null,"group_id":null,
         "post_id":"\(UUID().uuidString)","read_at":null,"pushed_at":null,
         "created_at":"2026-07-21T10:00:00Z","actor":null,"group":null,"post":null}
        """
        return try! TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
    }

    @Test func loadPopulatesItemsAndUnreadCount() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)

        await vm.load()

        #expect(vm.items.count == 2)
        #expect(vm.unreadCount == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadFailureSurfacesAnErrorAndKeepsListEmpty() async {
        let fake = FakeNotificationService()
        fake.fetchError = PostErrorStub.boom
        let vm = NotificationsViewModel(service: fake)

        await vm.load()

        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func markAllReadClearsBadgeOptimistically() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        await vm.markAllRead()

        #expect(vm.unreadCount == 0)
        #expect(vm.items.allSatisfy { !$0.isUnread })
        #expect(fake.markReadCalls == [nil])
    }

    /// The badge is the whole point of the tab — a failed write must not leave
    /// it lying about unread state.
    @Test func markAllReadRollsBackWhenTheWriteFails() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()
        fake.markReadError = PostErrorStub.boom

        await vm.markAllRead()

        #expect(vm.unreadCount == 2)
        #expect(vm.items.allSatisfy { $0.isUnread })
        #expect(vm.errorMessage != nil)
    }

    /// If a fresher `load()` completes while a mark-read write is in flight,
    /// the write's eventual failure must not resurrect the pre-load snapshot:
    /// the write never touched server state, and the newer load already
    /// replaced `items` with server truth, so that fresher data must survive.
    @Test func markAllReadRollbackDoesNotClobberAFresherLoad() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        fake.markReadError = PostErrorStub.boom
        let fresherItems = [unreadItem(), unreadItem(), unreadItem()]
        fake.onMarkRead = {
            fake.items = fresherItems
            fake.unread = 3
            await vm.load()
        }

        await vm.markAllRead()

        #expect(vm.items.count == 3)
        #expect(vm.unreadCount == 3)
    }

    /// A stale captured `item` (e.g. a double-tap before the first `await`
    /// yields) must not let two `markRead` calls each decrement the badge —
    /// the guard has to consult live view-model state, not the value that was
    /// passed in.
    @Test func doubleMarkReadWithStaleItemDecrementsOnce() async {
        let fake = FakeNotificationService()
        let item = unreadItem()
        fake.items = [item, unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        await vm.markRead(item)
        await vm.markRead(item)

        #expect(vm.unreadCount == 1)
    }

    /// A `loadMore()` that lands mid-flight during a failing mark-write must
    /// not have its appended rows wiped out by the mark-write's rollback: the
    /// page it fetched is newer truth, not the stale pre-write snapshot.
    @Test func loadMoreMidFlightSurvivesAFailingMarkWriteRollback() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        fake.markReadError = PostErrorStub.boom
        let olderPage = [unreadItem()]
        fake.onMarkRead = {
            fake.items = olderPage
            await vm.loadMore()
        }

        await vm.markAllRead()

        #expect(vm.items.count == 3)
    }

    /// If a second mark-write completes successfully while a first mark-write
    /// is still in flight, and the first then fails, the first's rollback
    /// must not resurrect rows the second already confirmed read server-side.
    @Test func secondMarkWriteSucceedingSurvivesFirstsFailureRollback() async {
        let fake = FakeNotificationService()
        let itemA = unreadItem()
        let itemB = unreadItem()
        fake.items = [itemA, itemB]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        fake.onMarkRead = {
            fake.onMarkRead = nil // avoid recursing into itself for B's own write
            await vm.markRead(itemB)
            fake.markReadError = PostErrorStub.boom
        }

        await vm.markRead(itemA)

        #expect(vm.unreadCount == 0)
        #expect(vm.items.allSatisfy { !$0.isUnread })
    }

    /// Once the server returns a page shorter than requested, pagination must
    /// be exhausted: without a `hasMore` flag, `items.last?.createdAt` stops
    /// changing, so the sentinel row's `.onAppear` re-fires `loadMore()` with
    /// the same cursor forever (pull-to-refresh, `markAllRead`, or scrolling
    /// away and back all re-trigger it). Assert a further `loadMore()` after
    /// the short page performs no additional fetch.
    @Test func loadMoreStopsFetchingOnceAShortPageExhaustsResults() async {
        let fake = FakeNotificationService()
        let fullPage = (0..<40).map { _ in unreadItem() }
        let shortPage = [unreadItem()]
        fake.pageQueue = [fullPage, shortPage]
        let vm = NotificationsViewModel(service: fake)

        await vm.load()
        #expect(vm.items.count == 40)

        await vm.loadMore()
        #expect(vm.items.count == 41)
        #expect(fake.fetchCallCount == 2)

        await vm.loadMore()
        #expect(vm.items.count == 41)
        #expect(fake.fetchCallCount == 2)
    }
}
