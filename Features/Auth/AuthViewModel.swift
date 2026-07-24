import Foundation
import Supabase

enum AuthRoute: Equatable {
    case signedOut, needsUsername, ready
}

@MainActor
@Observable
final class AuthViewModel {
    private(set) var session: Session?
    private(set) var profile: Profile?
    var isLoading = false
    var errorMessage: String?
    private(set) var usernameStatus: UsernameStatus = .idle

    private let provider: AuthProviding
    private var debounceTask: Task<Void, Never>?
    /// Runs before `provider.signOut()` tears down the session. Defaults to
    /// unregistering this device's push token — `unregister_device_token` is
    /// a SECURITY DEFINER RPC that resolves `auth.uid()`, so it must run
    /// while the session can still authorize it. Injectable (matching
    /// `GroupListViewModel.scheduleReminders` / `PostService.deleteRow`) so
    /// the unit suite never touches `PushRegistrar` or the network.
    private let willSignOut: @Sendable () async -> Void

    init(provider: AuthProviding = SupabaseService.shared,
         willSignOut: @escaping @Sendable () async -> Void = { await PushRegistrar.shared.unregisterBeforeLogout() }) {
        self.provider = provider
        self.willSignOut = willSignOut
        Task { await observe() }
    }

    var route: AuthRoute {
        let signedIn: Bool
        #if DEBUG
        signedIn = session != nil || _testHasSession
        #else
        signedIn = session != nil
        #endif
        guard signedIn else { return .signedOut }
        guard let profile else { return .needsUsername }
        return profile.usernameSet ? .ready : .needsUsername
    }

    var currentUserEmail: String? { session?.user.email }
    var currentUsername: String? { profile?.username }

    private func observe() async {
        for await (event, session) in provider.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                self.session = session
                await refreshProfile()
            case .signedOut:
                self.session = nil
                self.profile = nil
            default:
                break
            }
        }
    }

    private func refreshProfile() async {
        guard let userID = session?.user.id else { profile = nil; return }
        do {
            profile = try await provider.fetchProfile(userID: userID)
        } catch {
            // Real error (not "no row"): keep any existing profile, surface the error.
            errorMessage = mapAuthError(error)
        }
    }

    // MARK: Email

    func signUpEmail(email: String, password: String) async {
        await perform { try await self.provider.signUpEmail(email: email, password: password) }
    }

    func signInEmail(email: String, password: String) async {
        await perform { try await self.provider.signInEmail(email: email, password: password) }
    }

    // MARK: OAuth

    func signInWithGoogle() async { await performOAuth { try await self.provider.signInWithWebOAuth(.google) } }
    func signInWithDiscord() async { await performOAuth { try await self.provider.signInWithWebOAuth(.discord) } }

    func signOut() async {
        await willSignOut()
        await perform { try await self.provider.signOut() }
    }

    // MARK: Username flow

    /// Debounced entry point called from the text field's onChange.
    func usernameChanged(_ candidate: String) {
        debounceTask?.cancel()
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { usernameStatus = .idle; return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await self?.checkUsername(trimmed)
        }
    }

    /// Immediate (undebounced) availability check — used by tests and submit.
    func checkUsername(_ candidate: String) async {
        guard UsernameValidator.isValidFormat(candidate) else {
            usernameStatus = .invalid
            return
        }
        usernameStatus = .checking
        do {
            let available = try await provider.isUsernameAvailable(candidate)
            usernameStatus = available ? .available : .taken
        } catch {
            usernameStatus = .idle
        }
    }

    func submitUsername(_ candidate: String) async {
        guard let userID = session?.user.id else { return }
        guard UsernameValidator.isValidFormat(candidate) else { usernameStatus = .invalid; return }
        await perform {
            try await self.provider.setUsername(candidate, userID: userID)
            await self.refreshProfile()
        }
    }

    // MARK: Helpers

    private func perform(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { try await action() }
        catch { errorMessage = mapAuthError(error) }
    }

    /// Like `perform`, but treats provider cancellation as a silent no-op.
    private func performOAuth(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { try await action() }
        catch is CancellationError { /* no-op */ }
        catch let error as AuthProviderError where error == .cancelled { /* no-op */ }
        catch {
            // ASWebAuthenticationSession user-cancel is also a no-op.
            let ns = error as NSError
            if ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && ns.code == 1 { return }
            errorMessage = mapAuthError(error)
        }
    }

    #if DEBUG
    /// Test seam: set state directly without a live session.
    func applyForTesting(profile: Profile?, hasSession: Bool) {
        self.profile = profile
        if hasSession {
            // Minimal fake session marker; route only checks non-nil.
            self.session = nil
        }
        self._testHasSession = hasSession
    }
    private var _testHasSession = false
    #endif
}
