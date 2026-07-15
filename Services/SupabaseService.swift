import Foundation
import Supabase

/// Thin wrapper around the Supabase client. Holds the single shared `SupabaseClient`
/// instance, configured from `Secrets.plist` (see `AppSecrets`).
final class SupabaseService: Sendable {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        let secrets = AppSecrets.load()
        client = SupabaseClient(
            supabaseURL: secrets.supabaseURL,
            supabaseKey: secrets.supabaseAnonKey
        )
    }
}
