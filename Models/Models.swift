import Foundation

/// Codable models mirroring the Supabase database schema.
/// Property names use `CodingKeys` to map snake_case columns to Swift camelCase.

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var username: String
    var usernameSet: Bool
    var displayName: String?
    var avatarURL: URL?
    var bio: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case usernameSet = "username_set"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case createdAt = "created_at"
    }
}

// MARK: - Posts

enum PostKind: String, Codable, Sendable {
    case encouragement
    case checkIn = "check_in"
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    var kind: PostKind
    var title: String?
    var body: String?
    var sharedToTimeline: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case kind
        case title
        case body
        case sharedToTimeline = "shared_to_timeline"
        case createdAt = "created_at"
    }
}

struct Like: Codable, Hashable, Sendable {
    let userID: UUID
    let postID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case postID = "post_id"
        case createdAt = "created_at"
    }
}

struct Comment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    var content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case content
        case createdAt = "created_at"
    }
}

/// Payload for setting a user's chosen username.
struct ProfileUpdate: Encodable, Sendable {
    let username: String
    let username_set: Bool
}

// MARK: - Groups

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

// MARK: - Check-ins

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
    let postID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case windowID = "window_id"
        case postID = "post_id"
        case createdAt = "created_at"
    }
}

// MARK: - Post attachments

struct PostVerse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    var translation: String
    var book: String
    var chapter: Int
    var verseStart: Int
    var verseEnd: Int
    var referenceLabel: String
    var textSnapshot: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case translation
        case book
        case chapter
        case verseStart = "verse_start"
        case verseEnd = "verse_end"
        case referenceLabel = "reference_label"
        case textSnapshot = "text_snapshot"
        case position
    }
}

enum MediaType: String, Codable, Sendable {
    case image, link
}

struct PostMedia: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    var mediaType: MediaType
    var url: String
    var thumbnailURL: String?
    var title: String?
    var description: String?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case mediaType = "media_type"
        case url
        case thumbnailURL = "thumbnail_url"
        case title
        case description
        case position
    }
}

struct PostTag: Codable, Hashable, Sendable {
    let postID: UUID
    let taggedUserID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case taggedUserID = "tagged_user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Friends

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

// MARK: - Notifications

enum NotificationType: String, Codable, Sendable {
    case checkinReminder = "checkin_reminder"
    case memberCheckedIn = "member_checked_in"
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
    case groupInvite = "group_invite"
    case postLike = "post_like"
    case postComment = "post_comment"
    case postTag = "post_tag"
}

struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let recipientID: UUID
    var type: NotificationType
    var actorID: UUID?
    var groupID: UUID?
    var postID: UUID?
    var readAt: Date?
    var pushedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case type
        case actorID = "actor_id"
        case groupID = "group_id"
        case postID = "post_id"
        case readAt = "read_at"
        case pushedAt = "pushed_at"
        case createdAt = "created_at"
    }
}

struct DeviceToken: Codable, Hashable, Sendable {
    let userID: UUID
    let token: String
    var platform: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case updatedAt = "updated_at"
    }
}
