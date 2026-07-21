import Testing
import Foundation
@testable import BibleShare

struct CheckinModelTests {
    @Test func checkinTargetDecodes() throws {
        let json = """
        {"group_id":"aaaaaaaa-0000-0000-0000-000000000004","name":"Daily Crew",\
        "window_id":"eeeeeeee-0000-0000-0000-000000000005"}
        """.data(using: .utf8)!
        let target = try TestDecoder.postgrest().decode(CheckinTarget.self, from: json)
        #expect(target.groupID.uuidString.lowercased() == "aaaaaaaa-0000-0000-0000-000000000004")
        #expect(target.name == "Daily Crew")
        #expect(target.windowID.uuidString.lowercased() == "eeeeeeee-0000-0000-0000-000000000005")
        #expect(target.id == target.groupID)
    }

    @Test func checkInParamsEncodeLowercasedUUIDs() throws {
        let groupID = UUID()
        let params = CheckInParams(groupIDs: [groupID], title: "Hi", body: nil,
                                   verses: [], media: [], tagUserIDs: [])
        let data = try JSONEncoder().encode(params)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((obj["p_group_ids"] as? [String]) == [groupID.uuidString.lowercased()])
        #expect(obj["p_title"] as? String == "Hi")
        #expect(obj["p_body"] is NSNull || obj["p_body"] == nil)
        #expect((obj["p_verses"] as? [Any])?.isEmpty == true)
        #expect((obj["p_media"] as? [Any])?.isEmpty == true)
        #expect((obj["p_tag_user_ids"] as? [String]) == [])
    }

    @Test func feedItemDecodesCheckInKind() throws {
        let json = """
        {"id":"ffffffff-0000-0000-0000-0000000000aa","kind":"check_in",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001","title":null,"body":"Doing well",
         "created_at":"2026-07-20T13:00:00+00:00","author":null,
         "post_verses":[],"post_media":[],"post_tags":[],"likes":[],"comments":[]}
        """.data(using: .utf8)!
        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.kind == .checkIn)
    }

    @Test func feedItemKindDefaultsToEncouragementWhenAbsent() throws {
        // Older payloads (and every pre-Plan-5 test fixture) carry no kind.
        let json = """
        {"id":"ffffffff-0000-0000-0000-0000000000ab",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001","title":"T","body":null,
         "created_at":"2026-07-20T13:00:00+00:00","author":null,
         "post_verses":[],"post_media":[],"post_tags":[],"likes":[],"comments":[]}
        """.data(using: .utf8)!
        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.kind == .encouragement)
    }
}
