import Testing
import Foundation
@testable import BibleShare

struct FriendEdgeTests {
    private static let aliceID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    private static let bobID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!

    private func profileJSON(id: UUID, username: String, displayName: String?) -> String {
        let dn = displayName.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id.uuidString.lowercased())","username":"\(username)","username_set":true,\
        "display_name":\(dn),"avatar_url":null,"bio":null,\
        "created_at":"2026-07-15T12:00:00.000Z"}
        """
    }

    @Test func decodesPendingEdgeWithBothProfiles() throws {
        let json = """
        {"requester_id":"\(Self.aliceID.uuidString.lowercased())",
         "addressee_id":"\(Self.bobID.uuidString.lowercased())",
         "status":"pending","created_at":"2026-07-17T12:00:00.000Z","responded_at":null,
         "requester":\(profileJSON(id: Self.aliceID, username: "alice", displayName: "Alice A")),
         "addressee":\(profileJSON(id: Self.bobID, username: "bob", displayName: nil))}
        """.data(using: .utf8)!
        let edge = try TestDecoder.postgrest().decode(FriendEdge.self, from: json)
        #expect(edge.requesterID == Self.aliceID)
        #expect(edge.addresseeID == Self.bobID)
        #expect(edge.status == .pending)
        #expect(edge.respondedAt == nil)
        #expect(edge.requester?.username == "alice")
        #expect(edge.requester?.displayName == "Alice A")
        #expect(edge.addressee?.username == "bob")
        #expect(edge.addressee?.displayName == nil)
    }

    @Test func decodesAcceptedEdgeWithRespondedAt() throws {
        let json = """
        {"requester_id":"\(Self.aliceID.uuidString.lowercased())",
         "addressee_id":"\(Self.bobID.uuidString.lowercased())",
         "status":"accepted","created_at":"2026-07-17T12:00:00Z",
         "responded_at":"2026-07-17T12:05:00.000Z",
         "requester":\(profileJSON(id: Self.aliceID, username: "alice", displayName: nil)),
         "addressee":\(profileJSON(id: Self.bobID, username: "bob", displayName: "Bob B"))}
        """.data(using: .utf8)!
        let edge = try TestDecoder.postgrest().decode(FriendEdge.self, from: json)
        #expect(edge.status == .accepted)
        #expect(edge.respondedAt != nil)
        #expect(edge.id == "\(Self.aliceID.uuidString):\(Self.bobID.uuidString)")
    }

    @Test func otherPartyReturnsTheSideThatIsntMe() {
        let alice = Profile(id: Self.aliceID, username: "alice", usernameSet: true,
                            displayName: nil, avatarURL: nil, bio: nil, createdAt: Date())
        let bob = Profile(id: Self.bobID, username: "bob", usernameSet: true,
                          displayName: nil, avatarURL: nil, bio: nil, createdAt: Date())
        let edge = FriendEdge(requesterID: Self.aliceID, addresseeID: Self.bobID,
                              status: .accepted, createdAt: Date(), respondedAt: Date(),
                              requester: alice, addressee: bob)
        #expect(edge.otherParty(myID: Self.aliceID)?.username == "bob")
        #expect(edge.otherParty(myID: Self.bobID)?.username == "alice")
    }
}
