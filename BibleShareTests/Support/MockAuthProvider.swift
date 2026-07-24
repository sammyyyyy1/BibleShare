import Foundation
@testable import BibleShare
import Supabase

/// Configurable in-memory AuthProviding for view-model tests.
actor MockAuthProvider: AuthProviding {
    // Tunable behavior
    var profileToReturn: Profile?
    var availableResult: Bool = true
    var errorToThrow: Error?
    /// Test seam: fires at the start of `signOut()`, before `throwIfNeeded()`,
    /// so a test can record when the provider's sign-out actually ran and
    /// compare that against other async work (e.g. AuthViewModel's
    /// pre-sign-out hook) to assert ordering, not just that both happened.
    var onSignOut: (@Sendable () async -> Void)?

    private let stream: AsyncStream<(event: AuthChangeEvent, session: Session?)>
    private let continuation: AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation

    init() {
        var cont: AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation!
        stream = AsyncStream { cont = $0 }
        continuation = cont
    }

    nonisolated var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> { stream }
    var currentSession: Session? { get async { nil } }

    func emit(_ event: AuthChangeEvent, _ session: Session?) {
        continuation.yield((event: event, session: session))
    }

    func setProfile(_ p: Profile?) { profileToReturn = p }
    func setAvailable(_ b: Bool) { availableResult = b }
    func setError(_ e: Error?) { errorToThrow = e }
    func setOnSignOut(_ hook: (@Sendable () async -> Void)?) { onSignOut = hook }

    func signUpEmail(email: String, password: String) async throws { try throwIfNeeded() }
    func signInEmail(email: String, password: String) async throws { try throwIfNeeded() }
    func signInWithWebOAuth(_ provider: Provider) async throws { try throwIfNeeded() }
    func signOut() async throws {
        await onSignOut?()
        try throwIfNeeded()
    }

    func fetchProfile(userID: UUID) async throws -> Profile? {
        try throwIfNeeded(); return profileToReturn
    }
    func isUsernameAvailable(_ candidate: String) async throws -> Bool {
        try throwIfNeeded(); return availableResult
    }
    func setUsername(_ username: String, userID: UUID) async throws { try throwIfNeeded() }

    private func throwIfNeeded() throws {
        if let e = errorToThrow { errorToThrow = nil; throw e }
    }
}
