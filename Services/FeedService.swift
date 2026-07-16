import Foundation
import Supabase

final class FeedService: FeedServicing {
    static let shared = FeedService()

    /// The embedded select for a timeline row. RLS (posts_select_visible) is the
    /// only visibility gate — this query adds no auth logic of its own.
    private static let feedSelect = """
    id,author_id,title,body,created_at,\
    author:profiles!posts_author_id_profiles_fkey(*),\
    post_verses(*),\
    post_media(*),\
    post_tags(post_id,tagged_user_id,created_at,profiles(*)),\
    likes(count),\
    comments(count)
    """

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        var query = client.from("posts")
            .select(Self.feedSelect)
            .eq("kind", value: "encouragement")
            .eq("shared_to_timeline", value: true)
            // Plan 3 drops this filter and RLS surfaces friends' posts too.
            .eq("author_id", value: authorID.uuidString)

        if let before {
            // Pass the Date directly so supabase-swift's own PostgrestFilterValue
            // conformance formats it with fractional seconds — created_at is a
            // microsecond-precision timestamptz, and a default ISO8601DateFormatter
            // (whole seconds only) would move the cursor earlier than the true
            // instant, silently skipping posts in the truncated sub-second gap.
            query = query.lt("created_at", value: before)
        }

        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func likedPostIDs(userID: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        struct Row: Decodable { let post_id: UUID }
        let rows: [Row] = try await client.from("likes")
            .select("post_id")
            .eq("user_id", value: userID.uuidString)
            .in("post_id", values: ids.map(\.uuidString))
            .execute()
            .value
        return Set(rows.map(\.post_id))
    }
}
