import Foundation
import Supabase

/// Raised when the user cancels an interactive provider flow.
enum AuthProviderError: Error, Equatable {
    case cancelled
}

/// The auth surface AuthViewModel depends on. SupabaseService implements it;
/// tests use MockAuthProvider.
protocol AuthProviding: Sendable {
    var authStateChanges: AsyncStream<(AuthChangeEvent, Session?)> { get }
    var currentSession: Session? { get async }

    func signUpEmail(email: String, password: String) async throws
    func signInEmail(email: String, password: String) async throws
    func signInWithWebOAuth(_ provider: Provider) async throws
    func signOut() async throws

    func fetchProfile(userID: UUID) async throws -> Profile?
    func isUsernameAvailable(_ candidate: String) async throws -> Bool
    func setUsername(_ username: String, userID: UUID) async throws
}
