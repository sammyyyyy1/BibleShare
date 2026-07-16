import Foundation
@testable import BibleShare

/// Records what it was asked to do; fails on demand.
final class FakePostService: PostServicing, @unchecked Sendable {
    var createError: Error?
    var deleteError: Error?
    var likeError: Error?
    private(set) var createdParams: [CreateEncouragementParams] = []
    private(set) var deletedPosts: [UUID] = []
    private(set) var likeCalls: [(postID: UUID, liked: Bool)] = []
    private(set) var addedComments: [(postID: UUID, content: String)] = []
    var comments: [CommentItem] = []
    let newPostID = UUID()

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        createdParams.append(params)
        if let createError { throw createError }
        return newPostID
    }
    func deletePost(id: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedPosts.append(id)
    }
    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws {
        likeCalls.append((postID, liked))
        if let likeError { throw likeError }
    }
    func fetchComments(postID: UUID) async throws -> [CommentItem] { comments }
    func addComment(postID: UUID, userID: UUID, content: String) async throws {
        addedComments.append((postID, content))
    }
}

final class FakeMediaUploader: MediaUploading, @unchecked Sendable {
    var uploadError: Error?
    private(set) var uploadCount = 0
    private(set) var deletedPaths: [String] = []

    func upload(_ jpeg: Data, userID: UUID) async throws -> String {
        if let uploadError { throw uploadError }
        uploadCount += 1
        return "\(userID.uuidString.lowercased())/img\(uploadCount).jpg"
    }
    func delete(paths: [String]) async throws { deletedPaths.append(contentsOf: paths) }
    func signedURL(path: String) async throws -> URL { URL(string: "https://example.com/\(path)")! }
}

final class FakeUsernameResolver: UsernameResolving, @unchecked Sendable {
    var profiles: [String: Profile] = [:]
    func resolveExact(_ username: String) async throws -> Profile? {
        profiles[username.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()]
    }
}

final class FakeBibleService: BibleFetching, @unchecked Sendable {
    var error: Error?
    var passage = VersePassage(referenceLabel: "Joshua 1:9", text: "Be strong and courageous.")
    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage {
        if let error { throw error }
        return passage
    }
}

final class FakeFeedService: FeedServicing, @unchecked Sendable {
    var pages: [[FeedItem]] = []
    var liked: Set<UUID> = []
    var error: Error?
    private(set) var fetchCount = 0

    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        if let error { throw error }
        defer { fetchCount += 1 }
        return fetchCount < pages.count ? pages[fetchCount] : []
    }
    func likedPostIDs(userID: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        liked.intersection(ids)
    }
}

/// Builds a FeedItem without going through the network payload.
enum FeedItemFactory {
    static func make(id: UUID = UUID(),
                     authorID: UUID = UUID(),
                     title: String = "Title",
                     createdAt: Date = Date(),
                     likeCount: Int = 0,
                     isLiked: Bool = false) throws -> FeedItem {
        let json = """
        {"id":"\(id.uuidString.lowercased())","author_id":"\(authorID.uuidString.lowercased())",
         "title":"\(title)","body":null,
         "created_at":"\(ISO8601DateFormatter().string(from: createdAt))",
         "author":null,"post_verses":[],"post_media":[],"post_tags":[],
         "likes":[{"count":\(likeCount)}],"comments":[{"count":0}]}
        """.data(using: .utf8)!
        var item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        item.isLiked = isLiked
        return item
    }
}
