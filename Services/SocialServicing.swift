import Foundation

/// Protocol seams for the social layer, mirroring `AuthProviding`: live types
/// talk to Supabase, tests substitute fakes.

protocol PostServicing: Sendable {
    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID
    func deletePost(id: UUID, imagePaths: [String]) async throws
    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws
    func fetchComments(postID: UUID) async throws -> [CommentItem]
    func addComment(postID: UUID, userID: UUID, content: String) async throws
}

protocol FeedServicing: Sendable {
    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem]
    func likedPostIDs(userID: UUID, among: [UUID]) async throws -> Set<UUID>
}

protocol MediaUploading: Sendable {
    /// Returns the storage object path (NOT a URL) — this is what post_media.url stores.
    func upload(_ jpeg: Data, userID: UUID) async throws -> String
    func delete(paths: [String]) async throws
    func signedURL(path: String) async throws -> URL
}

protocol UsernameResolving: Sendable {
    /// Exact match only. Plan 2 deliberately exposes no prefix/fuzzy search;
    /// friend-scoped search arrives in Plan 3.
    func resolveExact(_ username: String) async throws -> Profile?
}

enum PostError {
    /// Maps a thrown error to user-facing copy, separating the recoverable
    /// (retry) from the terminal (surface and stop).
    static func message(for error: Error) -> String {
        if error is BibleError { return "Couldn't load that passage. Check the reference and try again." }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "You appear to be offline. Try again." }
        let text = "\(error)"
        if text.contains("title is required") { return "An encouragement needs a title." }
        if text.contains("own storage folder") { return "That image couldn't be attached. Try picking it again." }
        if text.contains("42501") || text.lowercased().contains("row-level security") {
            return "You don't have permission to do that."
        }
        return "Something went wrong. Please try again."
    }
}
