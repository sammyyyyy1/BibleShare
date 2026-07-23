import Foundation

/// Group entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.

enum CheckinCadence: String, Codable, Sendable {
    case none, daily, weekly
}

struct FellowshipGroup: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let creatorID: UUID
    var name: String
    var description: String?
    var checkinCadence: CheckinCadence
    var checkinTime: String?     // Postgres `time` decodes as "HH:mm:ss"
    var checkinWeekday: Int?
    var timezone: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case description
        case checkinCadence = "checkin_cadence"
        case checkinTime = "checkin_time"
        case checkinWeekday = "checkin_weekday"
        case timezone
        case createdAt = "created_at"
    }
}

struct GroupMember: Codable, Hashable, Sendable {
    let groupID: UUID
    let userID: UUID
    var role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}

enum InviteStatus: String, Codable, Sendable {
    case pending, accepted, declined
}

struct GroupInvite: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let inviterID: UUID
    let inviteeID: UUID
    var status: InviteStatus
    let createdAt: Date
    var respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case inviterID = "inviter_id"
        case inviteeID = "invitee_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

struct CheckinWindow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let opensAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case opensAt = "opens_at"
        case createdAt = "created_at"
    }
}

struct GroupCheckin: Codable, Hashable, Sendable {
    let groupID: UUID
    let userID: UUID
    let windowID: UUID
    let postID: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case windowID = "window_id"
        case postID = "post_id"
        case createdAt = "created_at"
    }
}
