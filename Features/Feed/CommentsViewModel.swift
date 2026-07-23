import Foundation

@MainActor
@Observable
final class CommentsViewModel {
    private(set) var comments: [CommentItem] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft = ""
    var errorMessage: String?

    private let posts: PostServicing

    init(posts: PostServicing = PostService.shared) {
        self.posts = posts
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load(postID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { comments = try await posts.fetchComments(postID: postID) }
        catch { errorMessage = PostError.message(for: error) }
    }

    func send(postID: UUID, userID: UUID) async {
        guard canSend else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await posts.addComment(postID: postID, userID: userID, content: content)
            draft = ""
            // Refetch so the new comment arrives with its author profile attached.
            await load(postID: postID)
        } catch {
            errorMessage = PostError.message(for: error)   // draft is kept
        }
    }
}
