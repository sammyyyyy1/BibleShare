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

/// A notification's post, kept deliberately thinner than `FeedItem` — a
/// notification row needs a label, not attachments, counts, or an author
/// embed it may not even be allowed to see.
struct PostSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: PostKind
    let title: String?
}

/// One notification row with its PostgREST embeds. `actor` is optional
/// because RLS can legitimately hide it; rendering must degrade, never blank.
struct NotificationItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let recipientID: UUID
    let type: NotificationType
    let actorID: UUID?
    let groupID: UUID?
    let postID: UUID?
    var readAt: Date?
    let createdAt: Date
    let actor: Profile?
    let group: FellowshipGroup?
    let post: PostSummary?

    var isUnread: Bool { readAt == nil }

    /// Neutral fallback so a hidden actor reads as "Someone liked your post"
    /// rather than an empty row. `display_name` is unconstrained text, so a
    /// blank (empty or whitespace-only) value is treated the same as absent
    /// and falls through to the next rung.
    var actorName: String {
        let displayName = actor?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return actor?.username ?? "Someone"
    }

    enum CodingKeys: String, CodingKey {
        case id, type, actor, group, post
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case groupID = "group_id"
        case postID = "post_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}
