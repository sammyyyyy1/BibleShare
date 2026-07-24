import Foundation
import Supabase

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

final class PostService: PostServicing {
    static let shared = PostService()

    private let client: SupabaseClient
    private let media: MediaUploading
    /// Deletes the `posts` row for the given id. Defaults to the real network
    /// call; unit tests substitute a fake so the storage-before-row ordering in
    /// `deletePost` can be proven without a reachable Supabase backend.
    private let deleteRow: @Sendable (UUID) async throws -> Void

    init(client: SupabaseClient = SupabaseService.shared.client,
         media: MediaUploading = MediaUploader.shared,
         deleteRow: (@Sendable (UUID) async throws -> Void)? = nil) {
        self.client = client
        self.media = media
        self.deleteRow = deleteRow ?? { id in
            try await client.from("posts").delete().eq("id", value: id.uuidString).execute()
        }
    }

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        try await client.rpc("create_encouragement", params: params).execute().value
    }

    func checkIn(_ params: CheckInParams) async throws -> UUID {
        try await client.rpc("check_in", params: params).execute().value
    }

    func deletePost(id: UUID, imagePaths: [String]) async throws {
        // Storage-first: if the sweep fails, the post (and its images) survives
        // and the user can retry — there is no cleanup job anywhere in this
        // system, so a silent leak here is permanent. Only delete the row once
        // the images are actually gone.
        if !imagePaths.isEmpty {
            try await media.delete(paths: imagePaths)
        }
        try await deleteRow(id)
    }

    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws {
        if liked {
            // PK (user_id, post_id) makes a double-tap race idempotent.
            try await client.from("likes")
                .upsert(Like(userID: userID, postID: postID, createdAt: Date()))
                .execute()
        } else {
            try await client.from("likes").delete()
                .eq("user_id", value: userID.uuidString)
                .eq("post_id", value: postID.uuidString)
                .execute()
        }
    }

    func fetchComments(postID: UUID) async throws -> [CommentItem] {
        try await client.from("comments")
            .select("id,post_id,author_id,content,created_at,author:profiles(*)")
            .eq("post_id", value: postID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func addComment(postID: UUID, userID: UUID, content: String) async throws {
        struct NewComment: Encodable {
            let post_id: String
            let author_id: String
            let content: String
        }
        try await client.from("comments")
            .insert(NewComment(post_id: postID.uuidString,
                               author_id: userID.uuidString,
                               content: content))
            .execute()
    }
}
