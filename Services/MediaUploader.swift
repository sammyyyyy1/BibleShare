import Foundation
import Supabase

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

    /// Exact match, one row max. No `like`/`ilike` — Plan 2 ships no search surface.
    func resolveExact(_ username: String) async throws -> Profile? {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        let rows: [Profile] = try await client.from("profiles")
            .select()
            .eq("username", value: cleaned)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}
