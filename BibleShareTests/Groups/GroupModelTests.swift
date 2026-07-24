import Testing
import Foundation
@testable import BibleShare

struct GroupModelTests {
    private static let aliceID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    private static let bobID   = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!
    private static let groupID = UUID(uuidString: "22222222-0000-0000-0000-0000000000b1")!

    @Test func decodesGroupListItemWithMemberCount() throws {
        let json = """
        {"role":"creator",
         "groups":{"id":"\(Self.groupID.uuidString.lowercased())",
                   "creator_id":"\(Self.aliceID.uuidString.lowercased())",
                   "name":"Group A","description":"Dawn crew",
                   "checkin_cadence":"none","checkin_time":null,"checkin_weekday":null,
                   "timezone":"America/New_York","created_at":"2026-07-18T12:00:00.000Z",
                   "group_members":[{"count":3}]}}
        """.data(using: .utf8)!
        let item = try TestDecoder.postgrest().decode(GroupListItem.self, from: json)
        #expect(item.role == "creator")
        #expect(item.group.name == "Group A")
        #expect(item.group.checkinCadence == .none)
        #expect(item.memberCount == 3)
        #expect(item.id == Self.groupID)
    }

    @Test func decodesGroupListItemMissingCountAsZero() throws {
        let json = """
        {"role":"member",
         "groups":{"id":"\(Self.groupID.uuidString.lowercased())",
                   "creator_id":"\(Self.aliceID.uuidString.lowercased())",
                   "name":"Group A","description":null,
                   "checkin_cadence":"none","checkin_time":null,"checkin_weekday":null,
                   "timezone":"America/New_York","created_at":"2026-07-18T12:00:00Z",
                   "group_members":[]}}
        """.data(using: .utf8)!
        let item = try TestDecoder.postgrest().decode(GroupListItem.self, from: json)
        #expect(item.memberCount == 0)
    }

    @Test func decodesGroupMemberRow() throws {
        let json = """
        {"user_id":"\(Self.bobID.uuidString.lowercased())","role":"member",
         "profile":{"id":"\(Self.bobID.uuidString.lowercased())","username":"bob",
                    "username_set":true,"display_name":"Bob B","avatar_url":null,"bio":null,
                    "created_at":"2026-07-01T12:00:00Z"}}
        """.data(using: .utf8)!
        let row = try TestDecoder.postgrest().decode(GroupMemberRow.self, from: json)
        #expect(row.userID == Self.bobID)
        #expect(row.role == "member")
        #expect(row.profile?.username == "bob")
    }

    @Test func decodesGroupInviteRowWithEmbeds() throws {
        let inviteID = UUID(uuidString: "33333333-0000-0000-0000-0000000000c1")!
        let json = """
        {"id":"\(inviteID.uuidString.lowercased())",
         "group_id":"\(Self.groupID.uuidString.lowercased())",
         "inviter_id":"\(Self.aliceID.uuidString.lowercased())",
         "invitee_id":"\(Self.bobID.uuidString.lowercased())",
         "status":"pending","created_at":"2026-07-18T12:00:00Z","responded_at":null,
         "group":{"id":"\(Self.groupID.uuidString.lowercased())","creator_id":"\(Self.aliceID.uuidString.lowercased())",
                  "name":"Group A","description":null,"checkin_cadence":"none","checkin_time":null,
                  "checkin_weekday":null,"timezone":"America/New_York","created_at":"2026-07-18T12:00:00Z"},
         "inviter":{"id":"\(Self.aliceID.uuidString.lowercased())","username":"alice","username_set":true,
                    "display_name":null,"avatar_url":null,"bio":null,"created_at":"2026-07-01T12:00:00Z"},
         "invitee":{"id":"\(Self.bobID.uuidString.lowercased())","username":"bob","username_set":true,
                    "display_name":null,"avatar_url":null,"bio":null,"created_at":"2026-07-01T12:00:00Z"}}
        """.data(using: .utf8)!
        let row = try TestDecoder.postgrest().decode(GroupInviteRow.self, from: json)
        #expect(row.id == inviteID)
        #expect(row.status == .pending)
        #expect(row.group?.name == "Group A")
        #expect(row.inviter?.username == "alice")
        #expect(row.invitee?.username == "bob")
    }

    @Test func encodesCreateGroupParams() throws {
        let params = CreateGroupParams(name: "Group A", description: "Dawn crew")
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        #expect(obj["p_name"] as? String == "Group A")
        #expect(obj["p_description"] as? String == "Dawn crew")
        #expect(obj["p_cadence"] as? String == "none")
        #expect(obj["p_timezone"] as? String == "America/New_York")
    }

    @Test func encodesGroupIDsInCreateEncouragementParams() throws {
        let params = CreateEncouragementParams(
            title: "Hi", body: nil, sharedToTimeline: false,
            groupIDs: [Self.groupID], verses: [], media: [], tagUserIDs: [])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        #expect((obj["p_group_ids"] as? [String])?.first == Self.groupID.uuidString.lowercased())
        #expect(obj["p_shared_to_timeline"] as? Bool == false)
    }
}
