import Foundation

/// Protocol seam for username → profile resolution. Backed by the
/// `find_profile_by_username` RPC (exact match only — never a prefix query).
protocol UsernameResolving: Sendable {
    /// Exact match only, routed through the `find_profile_by_username` RPC —
    /// after the Plan 3 profiles lockdown, direct table reads only see
    /// connected profiles. Friends-list filtering is client-side
    /// (`FriendsViewModel`), not part of this seam.
    func resolveExact(_ username: String) async throws -> Profile?
}
