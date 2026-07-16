import Foundation
import Supabase

final class PostService: PostServicing {
    static let shared = PostService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        try await client.rpc("create_encouragement", params: params).execute().value
    }

    func deletePost(id: UUID) async throws {
        try await client.from("posts").delete().eq("id", value: id.uuidString).execute()
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
