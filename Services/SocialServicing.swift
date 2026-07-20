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
    /// The Home feed: RLS (posts_select_visible) is the only visibility gate —
    /// the viewer's own timeline posts plus friends' shared_to_timeline posts.
    func fetchTimeline(before: Date?, limit: Int) async throws -> [FeedItem]
    func likedPostIDs(userID: UUID, among: [UUID]) async throws -> Set<UUID>
}

protocol MediaUploading: Sendable {
    /// Returns the storage object path (NOT a URL) — this is what post_media.url stores.
    func upload(_ jpeg: Data, userID: UUID) async throws -> String
    func delete(paths: [String]) async throws
    func signedURL(path: String) async throws -> URL
}

protocol UsernameResolving: Sendable {
    /// Exact match only, routed through the `find_profile_by_username` RPC —
    /// after the Plan 3 profiles lockdown, direct table reads only see
    /// connected profiles. Friends-list filtering is client-side
    /// (`FriendsViewModel`), not part of this seam.
    func resolveExact(_ username: String) async throws -> Profile?
}

protocol FriendServicing: Sendable {
    /// Resolves the username server-side and returns the resulting friendship
    /// row — `.pending` (request sent) or `.accepted` (reciprocal auto-accept).
    func sendRequest(username: String) async throws -> Friendship
    /// Accept (sets status + responded_at) or decline (deletes the row).
    /// Addressee-only, enforced by the RPC.
    func respond(requesterID: UUID, accept: Bool) async throws
    /// Every edge involving `userID` — RLS (`fr_select_parties`) scopes rows to
    /// the two parties; both parties' profiles are embedded.
    func fetchEdges(userID: UUID) async throws -> [FriendEdge]
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
        if text.contains("username not found") { return "We couldn't find that username." }
        if text.contains("cannot send a friend request to yourself") { return "You can't add yourself." }
        if text.contains("already friends") { return "You're already friends." }
        if text.contains("no pending friend request") { return "That request is no longer available." }
        if text.contains("42501") || text.lowercased().contains("row-level security") {
            return "You don't have permission to do that."
        }
        return "Something went wrong. Please try again."
    }
}
