import Foundation
import Supabase

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

final class FriendService: FriendServicing {
    static let shared = FriendService()

    /// Embedded select for a friendships row: both parties' profiles. RLS
    /// (fr_select_parties) limits rows to the viewer's own edges — this query
    /// adds no auth logic of its own.
    private static let edgeSelect = """
    requester_id,addressee_id,status,created_at,responded_at,\
    requester:profiles!friendships_requester_id_profiles_fkey(*),\
    addressee:profiles!friendships_addressee_id_profiles_fkey(*)
    """

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func sendRequest(username: String) async throws -> Friendship {
        struct Params: Encodable { let p_addressee_username: String }
        return try await client
            .rpc("send_friend_request", params: Params(p_addressee_username: username))
            .execute()
            .value
    }

    func respond(requesterID: UUID, accept: Bool) async throws {
        struct Params: Encodable {
            let p_requester_id: UUID
            let p_accept: Bool
        }
        try await client
            .rpc("respond_to_friend_request",
                 params: Params(p_requester_id: requesterID, p_accept: accept))
            .execute()
    }

    func fetchEdges(userID: UUID) async throws -> [FriendEdge] {
        try await client.from("friendships")
            .select(Self.edgeSelect)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
