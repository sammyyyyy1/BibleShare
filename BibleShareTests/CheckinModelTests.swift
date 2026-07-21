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
}
