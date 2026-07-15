import Foundation
import Supabase

/// Observable auth state backed by Supabase. Exposes sign-up / sign-in / sign-out
/// and keeps the current `Session` in sync with the SDK.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var session: Session?
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: SupabaseService

    var currentUserEmail: String? { session?.user.email }

    init(service: SupabaseService = .shared) {
        self.service = service
        Task { await observeAuthChanges() }
    }

    /// Restores any persisted session and streams future auth-state changes.
    private func observeAuthChanges() async {
        for await (event, session) in service.client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                self.session = session
            case .signedOut:
                self.session = nil
            default:
                break
            }
        }
    }

    func signUp(email: String, password: String) async {
        await perform {
            _ = try await service.client.auth.signUp(email: email, password: password)
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            _ = try await service.client.auth.signIn(email: email, password: password)
        }
    }

    func signOut() async {
        await perform {
            try await service.client.auth.signOut()
        }
    }

    /// Shared loading/error wrapper for auth calls.
    private func perform(_ action: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
