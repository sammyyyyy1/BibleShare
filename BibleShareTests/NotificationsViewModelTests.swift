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
}
