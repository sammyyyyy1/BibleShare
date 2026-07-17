import Foundation
@testable import BibleShare

/// Records what it was asked to do; fails on demand.
final class FakePostService: PostServicing, @unchecked Sendable {
    var createError: Error?
    var deleteError: Error?
    var likeError: Error?
    private(set) var createdParams: [CreateEncouragementParams] = []
    private(set) var deletedPosts: [UUID] = []
    private(set) var deletedImagePaths: [[String]] = []
    private(set) var likeCalls: [(postID: UUID, liked: Bool)] = []
    private(set) var addedComments: [(postID: UUID, content: String)] = []
    var comments: [CommentItem] = []
    let newPostID = UUID()

    /// Fires mid-flight inside `setLike`, before success/failure is decided —
    /// lets tests observe optimistic UI state while the "server call" is in flight.
    var onSetLike: (@MainActor () -> Void)?

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        createdParams.append(params)
        if let createError { throw createError }
        return newPostID
    }
    func deletePost(id: UUID, imagePaths: [String]) async throws {
        if let deleteError { throw deleteError }
        deletedPosts.append(id)
        deletedImagePaths.append(imagePaths)
    }
    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws {
        likeCalls.append((postID, liked))
        await onSetLike?()
        if let likeError { throw likeError }
    }
    func fetchComments(postID: UUID) async throws -> [CommentItem] { comments }
    func addComment(postID: UUID, userID: UUID, content: String) async throws {
        addedComments.append((postID, content))
    }
}

final class FakeMediaUploader: MediaUploading, @unchecked Sendable {
    var uploadError: Error?
    var deleteError: Error?
    private(set) var uploadCount = 0
    private(set) var deleteCallCount = 0
    private(set) var deletedPaths: [String] = []
    /// Fires as `delete` is invoked, before success/failure is decided — lets
    /// tests record a shared event timeline to prove call ordering against
    /// whatever happens after `media.delete` returns.
    var onDelete: (() -> Void)?

    func upload(_ jpeg: Data, userID: UUID) async throws -> String {
        if let uploadError { throw uploadError }
        uploadCount += 1
        return "\(userID.uuidString.lowercased())/img\(uploadCount).jpg"
    }
    func delete(paths: [String]) async throws {
        deleteCallCount += 1
        onDelete?()
        if let deleteError { throw deleteError }
        deletedPaths.append(contentsOf: paths)
    }
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
    /// Records the `before` cursor passed on every call, in order, so paging
    /// tests can verify which cursor was actually sent (not just that a call happened).
    private(set) var receivedCursors: [Date?] = []
    private(set) var receivedLimits: [Int] = []

    /// When set, the NEXT call to `fetchTimeline` suspends indefinitely (instead
    /// of returning) until the test calls `resumeSuspendedFetch()`. Resets itself
    /// after triggering once. Defaults to false, so every other test/use of this
    /// fake is unaffected. Lets tests put a call genuinely in flight to exercise
    /// concurrency guards, rather than merely sequencing calls.
    var suspendNextFetch = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var enteredFlightContinuation: CheckedContinuation<Void, Never>?

    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        receivedCursors.append(before)
        receivedLimits.append(limit)
        if suspendNextFetch {
            suspendNextFetch = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                suspensionContinuation = continuation
                enteredFlightContinuation?.resume()
                enteredFlightContinuation = nil
            }
        }
        if let error { throw error }
        defer { fetchCount += 1 }
        return fetchCount < pages.count ? pages[fetchCount] : []
    }
    func likedPostIDs(userID: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        liked.intersection(ids)
    }

    /// Suspends the caller until a fetch armed via `suspendNextFetch` has
    /// actually been entered (and thus is genuinely in flight), avoiding a
    /// racy `Task.yield()` guess at timing.
    func waitUntilFetchIsInFlight() async {
        guard suspensionContinuation == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enteredFlightContinuation = continuation
        }
    }

    /// Resumes a fetch suspended via `suspendNextFetch`. No-op if nothing is waiting.
    func resumeSuspendedFetch() {
        suspensionContinuation?.resume()
        suspensionContinuation = nil
    }
}

/// Builds a FeedItem without going through the network payload.
enum FeedItemFactory {
    static func make(id: UUID = UUID(),
                     authorID: UUID = UUID(),
                     title: String = "Title",
                     createdAt: Date = Date(),
                     likeCount: Int = 0,
                     isLiked: Bool = false,
                     media: [PostMedia] = []) throws -> FeedItem {
        let mediaJSON = media.map { m -> String in
            let thumbnail = m.thumbnailURL.map { "\"\($0)\"" } ?? "null"
            let mediaTitle = m.title.map { "\"\($0)\"" } ?? "null"
            let description = m.description.map { "\"\($0)\"" } ?? "null"
            return """
            {"id":"\(m.id.uuidString.lowercased())","post_id":"\(m.postID.uuidString.lowercased())",\
            "media_type":"\(m.mediaType.rawValue)","url":"\(m.url)","thumbnail_url":\(thumbnail),\
            "title":\(mediaTitle),"description":\(description),"position":\(m.position)}
            """
        }.joined(separator: ",")
        let json = """
        {"id":"\(id.uuidString.lowercased())","author_id":"\(authorID.uuidString.lowercased())",
         "title":"\(title)","body":null,
         "created_at":"\(ISO8601DateFormatter().string(from: createdAt))",
         "author":null,"post_verses":[],"post_media":[\(mediaJSON)],"post_tags":[],
         "likes":[{"count":\(likeCount)}],"comments":[{"count":0}]}
        """.data(using: .utf8)!
        var item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        item.isLiked = isLiked
        return item
    }
}
