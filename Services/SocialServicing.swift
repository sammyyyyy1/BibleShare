import Foundation

/// Protocol seams for the social layer, mirroring `AuthProviding`: live types
/// talk to Supabase, tests substitute fakes.

protocol PostServicing: Sendable {
    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID
    /// One check-in post fanned out to the given groups (each must have an
    /// open, unanswered window). Returns the new post id.
    func checkIn(_ params: CheckInParams) async throws -> UUID
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

protocol GroupServicing: Sendable {
    /// Create a group; the caller becomes its creator (a `group_members` row).
    func createGroup(_ params: CreateGroupParams) async throws -> FellowshipGroup
    /// The caller's groups (member of), each with role + member count.
    func fetchMyGroups(userID: UUID) async throws -> [GroupListItem]
    /// A group's members with embedded profiles.
    func fetchMembers(groupID: UUID) async throws -> [GroupMemberRow]
    /// A group's timeline (posts targeted at it), newest first.
    func fetchGroupTimeline(groupID: UUID, before: Date?, limit: Int) async throws -> [FeedItem]
    /// Creator-only invite by exact username; returns the pending invite row.
    func invite(groupID: UUID, username: String) async throws -> GroupInvite
    /// Pending invites addressed to the caller, with embedded group + inviter.
    func fetchIncomingInvites(userID: UUID) async throws -> [GroupInviteRow]
    /// Accept (adds membership) or decline (stamps status). Invitee-only.
    func respondToInvite(inviteID: UUID, accept: Bool) async throws
    /// The caller's groups with an open, unanswered check-in window.
    func fetchActiveCheckinTargets() async throws -> [CheckinTarget]
}

protocol NotificationServicing: Sendable {
    /// Newest first, keyset-paginated on `created_at`.
    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem]
    func unreadCount() async throws -> Int
    /// `nil` marks every unread notification read.
    func markRead(ids: [UUID]?) async throws
    /// Best-effort: a failure must never block sign-in or sign-out.
    func registerDeviceToken(_ token: String) async throws
    func unregisterDeviceToken(_ token: String) async throws
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
        if text.contains("already in this group") { return "You're already in this group." }
        if text.contains("already a member") { return "They're already a member." }
        if text.contains("only the group creator can invite") { return "Only the group's creator can invite people." }
        if text.contains("you can only post to groups you belong to") { return "You can only post to groups you belong to." }
        if text.contains("at least one destination") { return "Choose your timeline or at least one group." }
        if text.contains("group name must be") { return "A group name must be 1–60 characters." }
        if text.contains("no pending invite") { return "That invite is no longer available." }
        if text.contains("no active check-in window") { return "That check-in window has closed." }
        if text.contains("already checked in") { return "You've already checked in there." }
        if text.contains("a check-in needs at least one group") { return "Choose at least one group." }
        if text.contains("weekday must be between 0 and 6") { return "Pick a day of the week." }
        if text.contains("a check-in schedule needs a time") { return "Pick a time for the check-in." }
        if text.contains("a weekly schedule needs a weekday") { return "Pick a weekday for the check-in." }
        if text.contains("unknown timezone") { return "That time zone isn't recognized." }
        if text.contains("you can only tag people who can see this post") {
            return "You can only tag people who can see this post."
        }
        if text.contains("42501") || text.lowercased().contains("row-level security") {
            return "You don't have permission to do that."
        }
        return "Something went wrong. Please try again."
    }
}
