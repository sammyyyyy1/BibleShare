import Foundation

/// Notification entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.

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
