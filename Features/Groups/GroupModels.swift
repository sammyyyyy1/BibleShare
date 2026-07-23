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

/// A group in the caller's "my groups" list: the group row, the caller's role,
/// and the total member count. Decodes the
/// `group_members -> groups(*, group_members(count))` payload; `memberCount`
/// rides the nested `group_members(count)` aggregate.
struct GroupListItem: Decodable, Identifiable, Hashable, Sendable {
    let role: String
    let group: FellowshipGroup
    let memberCount: Int

    var id: UUID { group.id }

    init(role: String, group: FellowshipGroup, memberCount: Int) {
        self.role = role
        self.group = group
        self.memberCount = memberCount
    }

    enum CodingKeys: String, CodingKey { case role, groups }
    enum GroupKeys: String, CodingKey { case memberCount = "group_members" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        group = try c.decode(FellowshipGroup.self, forKey: .groups)
        let g = try c.nestedContainer(keyedBy: GroupKeys.self, forKey: .groups)
        memberCount = (try g.decodeIfPresent([CountRow].self, forKey: .memberCount))?.first?.count ?? 0
    }
}

/// A group member with their embedded profile (member list).
struct GroupMemberRow: Decodable, Identifiable, Hashable, Sendable {
    let userID: UUID
    let role: String
    let profile: Profile?

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case role, profile
        case userID = "user_id"
    }
}

/// A group_invites row plus embedded group + both parties' profiles
/// (incoming/outgoing invite screens). RLS (`gi_select_parties`) scopes rows.
struct GroupInviteRow: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let inviterID: UUID
    let inviteeID: UUID
    let status: InviteStatus
    let createdAt: Date
    let respondedAt: Date?
    let group: FellowshipGroup?
    let inviter: Profile?
    let invitee: Profile?

    enum CodingKeys: String, CodingKey {
        case id, status, group, inviter, invitee
        case groupID = "group_id"
        case inviterID = "inviter_id"
        case inviteeID = "invitee_id"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}
