import Foundation

/// Friendship entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.

enum FriendStatus: String, Codable, Sendable {
    case pending, accepted
}

struct Friendship: Codable, Hashable, Sendable {
    let requesterID: UUID
    let addresseeID: UUID
    var status: FriendStatus
    let createdAt: Date
    var respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

/// A `friendships` row plus both parties' embedded profiles — the friends-list
/// payload. RLS (`fr_select_parties`) already scopes rows to the viewer; the
/// embeds ride the friendships -> profiles FKs from 20260717010000.
struct FriendEdge: Decodable, Identifiable, Hashable, Sendable {
    let requesterID: UUID
    let addresseeID: UUID
    let status: FriendStatus
    let createdAt: Date
    let respondedAt: Date?
    let requester: Profile?
    let addressee: Profile?

    /// The directed pair is the table's PK — stable SwiftUI identity.
    var id: String { "\(requesterID.uuidString):\(addresseeID.uuidString)" }

    /// The profile of the side that isn't `myID`.
    func otherParty(myID: UUID) -> Profile? {
        myID == requesterID ? addressee : requester
    }

    enum CodingKeys: String, CodingKey {
        case requester, addressee, status
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}
