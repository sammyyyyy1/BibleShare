import Foundation
import Supabase

/// Thin wrapper around the Supabase client, conforming to AuthProviding.
final class SupabaseService: AuthProviding {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        let secrets = AppSecrets.load()
        client = SupabaseClient(
            supabaseURL: secrets.supabaseURL,
            supabaseKey: secrets.supabaseAnonKey
        )
    }

    // MARK: AuthProviding

    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    var currentSession: Session? {
        get async { try? await client.auth.session }
    }

    func signUpEmail(email: String, password: String) async throws {
        _ = try await client.auth.signUp(email: email, password: password)
    }

    func signInEmail(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func signInWithWebOAuth(_ provider: Provider) async throws {
        // Uses ASWebAuthenticationSession internally; callback scheme is taken
        // from redirectTo. Throws on user cancel — mapped by the caller.
        _ = try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: URL(string: "bibleshare://auth-callback")
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func fetchProfile(userID: UUID) async throws -> Profile? {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            return profile
        } catch {
            // `.single()` throws when zero rows exist (row not yet created).
            return nil
        }
    }

    func isUsernameAvailable(_ candidate: String) async throws -> Bool {
        try await client
            .rpc("is_username_available", params: ["candidate": candidate])
            .execute()
            .value
    }

    func setUsername(_ username: String, userID: UUID) async throws {
        try await client
            .from("profiles")
            .update(ProfileUpdate(username: username, username_set: true))
            .eq("id", value: userID.uuidString)
            .execute()
    }
}
