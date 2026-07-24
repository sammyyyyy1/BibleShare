import Testing
import Foundation
@testable import BibleShare

struct NotificationDestinationTests {
    private func item(_ type: NotificationType, post: UUID? = nil, group: UUID? = nil) -> NotificationItem {
        let json = """
        {"id":"\(UUID().uuidString)","recipient_id":"\(UUID().uuidString)",
         "type":"\(type.rawValue)","actor_id":null,
         "group_id":\(group.map { "\"\($0.uuidString)\"" } ?? "null"),
         "post_id":\(post.map { "\"\($0.uuidString)\"" } ?? "null"),
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":null,"group":null,"post":null}
        """
        return try! TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
    }

    @Test func postTypesRouteToThePost() {
        let p = UUID()
        for t in [NotificationType.postLike, .postComment, .postTag, .memberCheckedIn] {
            #expect(NotificationDestination.from(item(t, post: p)) == .post(p))
        }
    }

    @Test func reminderRoutesToItsGroup() {
        let g = UUID()
        #expect(NotificationDestination.from(item(.checkinReminder, group: g)) == .group(g))
    }

    @Test func inviteRoutesToTheInvitesScreenNotTheGroup() {
        // You are not a member yet, so the group timeline would be empty.
        #expect(NotificationDestination.from(item(.groupInvite, group: UUID())) == .invites)
    }

    @Test func friendTypesRouteToFriends() {
        #expect(NotificationDestination.from(item(.friendRequest)) == .friends)
        #expect(NotificationDestination.from(item(.friendAccepted)) == .friends)
    }

    /// A check-in whose post was deleted: group_checkins.post_id is ON DELETE
    /// SET NULL by design, so the ledger row survives with a null post.
    @Test func postTypeWithoutAPostFallsBackToItsGroup() {
        let g = UUID()
        #expect(NotificationDestination.from(item(.memberCheckedIn, group: g)) == .group(g))
    }

    @Test func postTypeWithNeitherIsUnroutable() {
        #expect(NotificationDestination.from(item(.postLike)) == nil)
    }
}
