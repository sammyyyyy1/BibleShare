import Foundation
import Supabase

final class NotificationService: NotificationServicing {
    static let shared = NotificationService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    /// notifications.actor_id -> profiles is the redundant FK added in Task 2;
    /// without it PostgREST cannot embed a profile through auth.users.
    private static let select = """
    id,recipient_id,type,actor_id,group_id,post_id,read_at,created_at,\
    actor:profiles(*),group:groups(*),post:posts(id,kind,title)
    """

    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem] {
        var query = client.from("notifications").select(Self.select)
        if let before {
            query = query.lt("created_at", value: ISO8601DateFormatter().string(from: before))
        }
        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func unreadCount() async throws -> Int {
        // RLS (notif_select_own) already scopes this to the caller.
        let response = try await client.from("notifications")
            .select("id", head: true, count: .exact)
            .is("read_at", value: nil)
            .execute()
        return response.count ?? 0
    }

    func markRead(ids: [UUID]?) async throws {
        struct Params: Encodable { let p_ids: [String]? }
        try await client
            .rpc("mark_notifications_read", params: Params(p_ids: ids?.map(\.uuidString)))
            .execute()
    }

    func registerDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String; let p_platform: String }
        try await client
            .rpc("register_device_token", params: Params(p_token: token, p_platform: "ios"))
            .execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String }
        try await client
            .rpc("unregister_device_token", params: Params(p_token: token))
            .execute()
    }
}
