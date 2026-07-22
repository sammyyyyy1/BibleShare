import Foundation

/// Where tapping a notification goes. A pure mapping so it can be unit-tested
/// away from navigation, and so the APNs tap handler can reuse it verbatim.
enum NotificationDestination: Equatable, Hashable, Sendable {
    case post(UUID)
    case group(UUID)
    case invites
    case friends

    static func from(_ item: NotificationItem) -> NotificationDestination? {
        switch item.type {
        case .postLike, .postComment, .postTag, .memberCheckedIn:
            // group_checkins.post_id is ON DELETE SET NULL by design, so a
            // check-in notification can outlive its post. Fall back to the group.
            if let postID = item.postID { return .post(postID) }
            if let groupID = item.groupID { return .group(groupID) }
            return nil
        case .checkinReminder:
            return item.groupID.map { .group($0) }
        case .groupInvite:
            // Not a member yet — the group timeline would be empty.
            return .invites
        case .friendRequest, .friendAccepted:
            return .friends
        }
    }
}

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var items: [NotificationItem] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: NotificationServicing
    private let pageSize = 40

    init(service: NotificationServicing = NotificationService.shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await service.fetchNotifications(before: nil, limit: pageSize)
            unreadCount = try await service.unreadCount()
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore() async {
        guard let oldest = items.last?.createdAt, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items += try await service.fetchNotifications(before: oldest, limit: pageSize)
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func markAllRead() async {
        // Optimistic: the badge is the point of the tab, so it clears now and
        // rolls back wholesale if the write fails.
        let snapshotItems = items
        let snapshotCount = unreadCount
        let now = Date()
        for index in items.indices where items[index].isUnread { items[index].readAt = now }
        unreadCount = 0
        do {
            try await service.markRead(ids: nil)
        } catch {
            items = snapshotItems
            unreadCount = snapshotCount
            errorMessage = PostError.message(for: error)
        }
    }

    func markRead(_ item: NotificationItem) async {
        guard item.isUnread, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let snapshotItems = items
        let snapshotCount = unreadCount
        items[index].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
        do {
            try await service.markRead(ids: [item.id])
        } catch {
            items = snapshotItems
            unreadCount = snapshotCount
            errorMessage = PostError.message(for: error)
        }
    }
}
