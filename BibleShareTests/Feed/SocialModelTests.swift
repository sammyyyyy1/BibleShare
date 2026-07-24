import Testing
import Foundation
@testable import BibleShare

struct SocialModelTests {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "bad date \(s)"))
        }
        return d
    }

    @Test func decodesGroupWithSchedule() throws {
        let json = """
        {"id":"11111111-0000-0000-0000-0000000000aa",
         "creator_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "name":"Morning Prayer","description":null,
         "checkin_cadence":"weekly","checkin_time":"08:00:00","checkin_weekday":1,
         "timezone":"America/New_York","created_at":"2026-07-15T12:00:00.000Z"}
        """.data(using: .utf8)!
        let g = try decoder().decode(FellowshipGroup.self, from: json)
        #expect(g.checkinCadence == .weekly)
        #expect(g.checkinTime == "08:00:00")
        #expect(g.checkinWeekday == 1)
    }

    @Test func decodesInvitePendingNullResponded() throws {
        let json = """
        {"id":"22222222-0000-0000-0000-0000000000bb",
         "group_id":"11111111-0000-0000-0000-0000000000aa",
         "inviter_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "invitee_id":"bbbbbbbb-0000-0000-0000-000000000002",
         "status":"pending","created_at":"2026-07-15T12:00:00Z","responded_at":null}
        """.data(using: .utf8)!
        let inv = try decoder().decode(GroupInvite.self, from: json)
        #expect(inv.status == .pending)
        #expect(inv.respondedAt == nil)
    }

    @Test func decodesVerseRange() throws {
        let json = """
        {"id":"33333333-0000-0000-0000-0000000000cc",
         "post_id":"99999990-0000-0000-0000-000000000002",
         "translation":"WEB","book":"John","chapter":3,
         "verse_start":16,"verse_end":17,"reference_label":"John 3:16–17",
         "text_snapshot":"For God so loved the world...","position":0}
        """.data(using: .utf8)!
        let v = try decoder().decode(PostVerse.self, from: json)
        #expect(v.book == "John")
        #expect(v.verseStart == 16 && v.verseEnd == 17)
        #expect(v.referenceLabel == "John 3:16–17")
    }

    @Test func decodesFriendshipAndNotification() throws {
        let fjson = """
        {"requester_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "addressee_id":"bbbbbbbb-0000-0000-0000-000000000002",
         "status":"accepted","created_at":"2026-07-15T12:00:00Z",
         "responded_at":"2026-07-15T12:05:00Z"}
        """.data(using: .utf8)!
        let f = try decoder().decode(Friendship.self, from: fjson)
        #expect(f.status == .accepted)
        #expect(f.respondedAt != nil)

        let njson = """
        {"id":"44444444-0000-0000-0000-0000000000dd",
         "recipient_id":"bbbbbbbb-0000-0000-0000-000000000002",
         "type":"member_checked_in",
         "actor_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "group_id":"11111111-0000-0000-0000-0000000000aa","post_id":null,
         "read_at":null,"pushed_at":null,"created_at":"2026-07-15T12:00:00Z"}
        """.data(using: .utf8)!
        let n = try decoder().decode(AppNotification.self, from: njson)
        #expect(n.type == .memberCheckedIn)
        #expect(n.postID == nil)
        #expect(n.groupID != nil)
    }
}
