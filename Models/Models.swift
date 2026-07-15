import Foundation

/// Codable models mirroring the Supabase database schema.
/// Property names use `CodingKeys` to map snake_case columns to Swift camelCase.

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var username: String
    var displayName: String?
    var avatarURL: URL?
    var bio: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case createdAt = "created_at"
    }
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    var content: String
    var mediaURL: URL?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case content
        case mediaURL = "media_url"
        case createdAt = "created_at"
    }
}

struct Follow: Codable, Hashable, Sendable {
    let followerID: UUID
    let followeeID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followeeID = "followee_id"
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
