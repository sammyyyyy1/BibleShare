import Foundation

/// Post content entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.

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
