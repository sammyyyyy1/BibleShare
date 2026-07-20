import Foundation

/// Read-side DTOs decoding the PostgREST embedded payloads. Row models
/// (`Post`, `PostVerse`, …) live in Models.swift; these are the join shapes.

/// PostgREST renders `likes(count)` as `[{"count": 3}]`.
struct CountRow: Decodable, Hashable, Sendable {
    let count: Int
}

struct TaggedUser: Decodable, Identifiable, Hashable, Sendable {
    let taggedUserID: UUID
    let profile: Profile?

    var id: UUID { taggedUserID }

    enum CodingKeys: String, CodingKey {
        case taggedUserID = "tagged_user_id"
        case profile = "profiles"
    }
}

/// One timeline row: the post, its author, its attachments and its tallies.
struct FeedItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String?
    let body: String?
    let createdAt: Date
    let author: Profile?
    var verses: [PostVerse]
    var media: [PostMedia]
    var tags: [TaggedUser]
    /// Mutable so the cell can update optimistically.
    var likeCount: Int
    var commentCount: Int
    /// Not part of the payload — filled from the companion liked-ids query.
    var isLiked: Bool = false

    var images: [PostMedia] { media.filter { $0.mediaType == .image } }
    var links: [PostMedia] { media.filter { $0.mediaType == .link } }

    enum CodingKeys: String, CodingKey {
        case id, title, body, author, likes, comments
        case authorID = "author_id"
        case createdAt = "created_at"
        case verses = "post_verses"
        case media = "post_media"
        case tags = "post_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        author = try c.decodeIfPresent(Profile.self, forKey: .author)
        verses = (try c.decodeIfPresent([PostVerse].self, forKey: .verses) ?? [])
            .sorted { $0.position < $1.position }
        media = (try c.decodeIfPresent([PostMedia].self, forKey: .media) ?? [])
            .sorted { $0.position < $1.position }
        tags = try c.decodeIfPresent([TaggedUser].self, forKey: .tags) ?? []
        likeCount = (try c.decodeIfPresent([CountRow].self, forKey: .likes))?.first?.count ?? 0
        commentCount = (try c.decodeIfPresent([CountRow].self, forKey: .comments))?.first?.count ?? 0
    }
}

/// A comment plus its author profile.
struct CommentItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let content: String
    let createdAt: Date
    let author: Profile?

    enum CodingKeys: String, CodingKey {
        case id, content, author
        case postID = "post_id"
        case authorID = "author_id"
        case createdAt = "created_at"
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
