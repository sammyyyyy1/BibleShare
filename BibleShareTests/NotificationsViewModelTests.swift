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
}
