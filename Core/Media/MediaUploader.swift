import Foundation
import Supabase

protocol MediaUploading: Sendable {
    /// Returns the storage object path (NOT a URL) — this is what post_media.url stores.
    func upload(_ jpeg: Data, userID: UUID) async throws -> String
    func delete(paths: [String]) async throws
    func signedURL(path: String) async throws -> URL
}

final class MediaUploader: MediaUploading {
    static let shared = MediaUploader()

    private static let bucket = "media"

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func upload(_ jpeg: Data, userID: UUID) async throws -> String {
        // LOWERCASE: the storage policy compares against auth.uid()::text, which
        // Postgres renders lowercase. UUID.uuidString is uppercase — a raw
        // uuidString here makes every upload fail the folder-ownership check.
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from(Self.bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    func delete(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await client.storage.from(Self.bucket).remove(paths: paths)
    }

    func signedURL(path: String) async throws -> URL {
        try await client.storage.from(Self.bucket).createSignedURL(path: path, expiresIn: 3600)
    }
}

final class ProfileService: UsernameResolving {
    static let shared = ProfileService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    /// Exact match via the `find_profile_by_username` RPC. After the Plan 3
    /// profiles lockdown, a direct `.from("profiles")` query only sees
    /// connected profiles — the RPC is the discovery path. Signature and
    /// semantics unchanged for tag-picker consumers and fakes.
    func resolveExact(_ username: String) async throws -> Profile? {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        struct Params: Encodable { let p_username: String }
        let rows: [Profile] = try await client
            .rpc("find_profile_by_username", params: Params(p_username: cleaned))
            .execute()
            .value
        return rows.first
    }
}
