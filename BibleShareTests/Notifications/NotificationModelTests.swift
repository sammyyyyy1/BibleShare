import Testing
import Foundation
@testable import BibleShare

struct NotificationModelTests {
    @Test func decodesRowWithEmbeddedActorGroupAndPost() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":"33333333-3333-3333-3333-333333333333",
         "group_id":null,"post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":{"id":"33333333-3333-3333-3333-333333333333","username":"ruth",
                  "username_set":true,"display_name":"Ruth","avatar_url":null,
                  "bio":null,"created_at":"2026-07-01T00:00:00Z"},
         "group":null,
         "post":{"id":"44444444-4444-4444-4444-444444444444",
                 "kind":"encouragement","title":"Morning"}}
        """
        let item = try TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.type == .postLike)
        #expect(item.actor?.username == "ruth")
        #expect(item.post?.title == "Morning")
        #expect(item.isUnread)
    }

    /// RLS can legitimately hide the actor (a co-member who left, an actor whose
    /// only link was a deleted post). The row must still decode and render.
    @Test func decodesWithNullActorAndFallsBackToNeutralCopy() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":null,"group_id":null,
         "post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":"2026-07-21T11:00:00Z","pushed_at":null,
         "created_at":"2026-07-21T10:00:00Z",
         "actor":null,"group":null,"post":null}
        """
        let item = try TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.actor == nil)
        #expect(item.actorName == "Someone")
        #expect(item.isUnread == false)
    }

    /// The middle rung: no display name set, but a real username. A broken
    /// fallback that swaps the first two rungs would still pass every other
    /// test in this file, so this must assert on `actorName` directly.
    @Test func actorNameFallsBackToUsernameWhenDisplayNameIsNil() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":"33333333-3333-3333-3333-333333333333",
         "group_id":null,"post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":{"id":"33333333-3333-3333-3333-333333333333","username":"ruth",
                  "username_set":true,"display_name":null,"avatar_url":null,
                  "bio":null,"created_at":"2026-07-01T00:00:00Z"},
         "group":null,
         "post":{"id":"44444444-4444-4444-4444-444444444444",
                 "kind":"encouragement","title":"Morning"}}
        """
        let item = try TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.actorName == "ruth")
    }

    /// `display_name` is unconstrained text, so an empty (or whitespace-only)
    /// string is a real possible value, not just an absent one. `??` alone
    /// wouldn't catch it, so `actorName` must treat blank the same as nil.
    @Test func actorNameFallsBackToUsernameWhenDisplayNameIsBlank() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":"33333333-3333-3333-3333-333333333333",
         "group_id":null,"post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":{"id":"33333333-3333-3333-3333-333333333333","username":"ruth",
                  "username_set":true,"display_name":"","avatar_url":null,
                  "bio":null,"created_at":"2026-07-01T00:00:00Z"},
         "group":null,
         "post":{"id":"44444444-4444-4444-4444-444444444444",
                 "kind":"encouragement","title":"Morning"}}
        """
        let item = try TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.actorName == "ruth")
    }

    @Test func checkinReminderHasNoActorByDesign() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"checkin_reminder","actor_id":null,
         "group_id":"55555555-5555-5555-5555-555555555555","post_id":null,
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":null,
         "group":{"id":"55555555-5555-5555-5555-555555555555",
                  "creator_id":"22222222-2222-2222-2222-222222222222",
                  "name":"Daily Crew","description":null,
                  "checkin_cadence":"daily","checkin_time":"08:00:00",
                  "checkin_weekday":null,"timezone":"UTC",
                  "created_at":"2026-07-01T00:00:00Z"},
         "post":null}
        """
        let item = try TestDecoder.postgrest().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.type == .checkinReminder)
        #expect(item.group?.name == "Daily Crew")
    }
}
