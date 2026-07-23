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
