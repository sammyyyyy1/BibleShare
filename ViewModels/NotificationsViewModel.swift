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
            // notifications.post_id is ON DELETE CASCADE, so a live notification
            // always still has its post — the post-first branch is the real
            // path. The group fallback is defensive only (a member_checked_in
            // row always also carries group_id); it costs nothing and keeps the
            // function total if a future type sets group_id without post_id.
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

    /// False once `loadMore()` gets back a page shorter than requested —
    /// that's the server's way of saying there's nothing older left. Without
    /// this, `items.last?.createdAt` stops changing on an empty/short page
    /// and the sentinel row's `.onAppear` re-fires `loadMore()` with the same
    /// cursor forever (pull-to-refresh, `markAllRead`, or scrolling away and
    /// back all make it visible again).
    ///
    /// A fresh `load()` always resets this to `true`: it doesn't yet know
    /// whether the server has more beyond this page (a short first page can
    /// legitimately be the server's whole result set, e.g. right after
    /// account creation), so it defers that determination to the next
    /// `loadMore()` rather than guessing from the first page's size alone.
    private(set) var hasMore = true

    private let service: NotificationServicing
    private let pageSize = 40

    /// Bumped by every path that writes newer truth into `items`/`unreadCount`:
    /// `load()` after it assigns from the server, `loadMore()` after it
    /// appends a page, and `markAllRead()`/`markRead(_:)` after their write
    /// succeeds. A mark-read rollback captures this before its `await` and
    /// compares it again in its `catch`: if it moved, something newer has
    /// already landed on top of the snapshot it would otherwise restore, so
    /// the rollback must not happen — it would clobber confirmed state with
    /// stale pre-write data.
    private var generation = 0

    init(service: NotificationServicing = NotificationService.shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await service.fetchNotifications(before: nil, limit: pageSize)
            hasMore = true
            unreadCount = try await service.unreadCount()
            generation += 1
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore() async {
        guard hasMore, let oldest = items.last?.createdAt, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.fetchNotifications(before: oldest, limit: pageSize)
            items += page
            hasMore = page.count >= pageSize
            generation += 1
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func markAllRead() async {
        // Optimistic: the badge is the point of the tab, so it clears now and
        // rolls back wholesale if the write fails.
        let snapshotItems = items
        let snapshotCount = unreadCount
        let snapshotGeneration = generation
        let now = Date()
        for index in items.indices where items[index].isUnread { items[index].readAt = now }
        unreadCount = 0
        do {
            try await service.markRead(ids: nil)
            generation += 1
        } catch {
            // If `generation` moved while this write was in flight, something
            // newer has already landed on top of this snapshot — a fresher
            // `load()`/`loadMore()`, or another mark-write that succeeded —
            // and already replaced `items`/`unreadCount` with truth this
            // failed write never touched. Restoring the snapshot would
            // clobber that newer state. Only roll back when nothing newer
            // has superseded the snapshot.
            if generation == snapshotGeneration {
                items = snapshotItems
                unreadCount = snapshotCount
            }
            errorMessage = PostError.message(for: error)
        }
    }

    func markRead(_ item: NotificationItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index].isUnread else { return }
        let snapshotItems = items
        let snapshotCount = unreadCount
        let snapshotGeneration = generation
        items[index].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
        do {
            try await service.markRead(ids: [item.id])
            generation += 1
        } catch {
            // See markAllRead: a generation bump means something newer already
            // superseded this snapshot, so leave the fresher state alone.
            if generation == snapshotGeneration {
                items = snapshotItems
                unreadCount = snapshotCount
            }
            errorMessage = PostError.message(for: error)
        }
    }
}
