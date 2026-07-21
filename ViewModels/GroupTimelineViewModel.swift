import Foundation

@MainActor
@Observable
final class GroupTimelineViewModel: FeedLikeHandling {
    static let pageSize = 20

    let groupID: UUID
    let myID: UUID

    // Settable (not private(set)) so the FeedLikeHandling mixin can mutate it.
    var items: [FeedItem] = []
    private(set) var members: [GroupMemberRow] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    private(set) var isInviting = false
    var inviteError: String?
    var inviteStatus: String?

    private let groupService: GroupServicing
    private let feed: FeedServicing
    private let posts: PostServicing

    init(groupID: UUID, myID: UUID,
         groupService: GroupServicing = GroupService.shared,
         feed: FeedServicing = FeedService.shared,
         posts: PostServicing = PostService.shared) {
        self.groupID = groupID
        self.myID = myID
        self.groupService = groupService
        self.feed = feed
        self.posts = posts
    }

    var likeFeed: FeedServicing { feed }
    var likePosts: PostServicing { posts }

    var isCreator: Bool {
        members.contains { $0.userID == myID && $0.role == "creator" }
    }

    func load() async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let membersTask = groupService.fetchMembers(groupID: groupID)
            let page = try await groupService.fetchGroupTimeline(groupID: groupID, before: nil, limit: Self.pageSize)
            members = try await membersTask
            items = try await markLiked(page, userID: myID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, let cursor = items.last?.createdAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await groupService.fetchGroupTimeline(groupID: groupID, before: cursor, limit: Self.pageSize)
            items += try await markLiked(page, userID: myID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    /// Group timelines always like as the current member; wraps the mixin toggle.
    func toggleLike(itemID: UUID) async {
        await toggleLike(itemID: itemID, userID: myID)
    }

    func invite(username: String) async {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty, !isInviting else { return }
        isInviting = true
        inviteError = nil
        inviteStatus = nil
        defer { isInviting = false }
        do {
            _ = try await groupService.invite(groupID: groupID, username: cleaned)
            inviteStatus = "Invite sent."
        } catch {
            inviteError = PostError.message(for: error)
        }
    }
}
