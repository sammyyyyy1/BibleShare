import Foundation

/// Shared-kernel identity models. `Profile` is decoded by Auth, Profile, Feed,
/// Friends, Groups, and Notifications, so it lives in Core rather than a feature.

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

/// Payload for setting a user's chosen username.
struct ProfileUpdate: Encodable, Sendable {
    let username: String
    let username_set: Bool
}
