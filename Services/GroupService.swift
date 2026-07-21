import Foundation
import Supabase

final class GroupService: GroupServicing {
    static let shared = GroupService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func createGroup(_ params: CreateGroupParams) async throws -> FellowshipGroup {
        try await client.rpc("create_group", params: params).execute().value
    }

    func fetchMyGroups(userID: UUID) async throws -> [GroupListItem] {
        // RLS shows every group_members row of my groups; the eq filter narrows
        // to MY memberships. The nested group_members(count) is the total roster.
        try await client.from("group_members")
            .select("role,groups(*,group_members(count))")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
    }

    func fetchMembers(groupID: UUID) async throws -> [GroupMemberRow] {
        try await client.from("group_members")
            .select("user_id,role,profile:profiles!group_members_user_id_profiles_fkey(*)")
            .eq("group_id", value: groupID.uuidString)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    func fetchGroupTimeline(groupID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        // Group timeline = posts targeted at the group, via post_groups. The
        // nested posts embed reuses the exact feed shape; RLS gates visibility.
        struct Row: Decodable { let post: FeedItem? }
        var query = client.from("post_groups")
            .select("created_at,post:posts(\(FeedService.feedSelect))")
            .eq("group_id", value: groupID.uuidString)

        if let before {
            // post_groups.created_at == posts.created_at (same transaction now()),
            // so this cursor matches the FeedItem.createdAt the ViewModel pages on.
            query = query.lt("created_at", value: before)
        }

        let rows: [Row] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.compactMap(\.post)
    }

    func invite(groupID: UUID, username: String) async throws -> GroupInvite {
        struct Params: Encodable { let p_group_id: UUID; let p_invitee_username: String }
        return try await client
            .rpc("invite_to_group", params: Params(p_group_id: groupID, p_invitee_username: username))
            .execute()
            .value
    }

    func fetchIncomingInvites(userID: UUID) async throws -> [GroupInviteRow] {
        try await client.from("group_invites")
            .select("""
            id,group_id,inviter_id,invitee_id,status,created_at,responded_at,\
            group:groups(*),\
            inviter:profiles!group_invites_inviter_id_profiles_fkey(*),\
            invitee:profiles!group_invites_invitee_id_profiles_fkey(*)
            """)
            .eq("invitee_id", value: userID.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func respondToInvite(inviteID: UUID, accept: Bool) async throws {
        struct Params: Encodable { let p_invite_id: UUID; let p_accept: Bool }
        try await client
            .rpc("respond_to_invite", params: Params(p_invite_id: inviteID, p_accept: accept))
            .execute()
    }

    func fetchActiveCheckinTargets() async throws -> [CheckinTarget] {
        try await client.rpc("active_checkin_targets").execute().value
    }
}
