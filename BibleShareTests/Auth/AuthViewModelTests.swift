import Testing
import Foundation
@testable import BibleShare

@MainActor
struct AuthViewModelTests {
    private func makeProfile(usernameSet: Bool) -> Profile {
        Profile(id: UUID(), username: "user_abc", usernameSet: usernameSet,
                displayName: nil, avatarURL: nil, bio: nil, createdAt: Date())
    }

    @Test func routeIsSignedOutWithoutProfile() {
        let vm = AuthViewModel(provider: MockAuthProvider())
        #expect(vm.route == .signedOut)
    }

    @Test func routeNeedsUsernameWhenFlagFalse() {
        let vm = AuthViewModel(provider: MockAuthProvider())
        vm.applyForTesting(profile: makeProfile(usernameSet: false), hasSession: true)
        #expect(vm.route == .needsUsername)
    }

    @Test func routeReadyWhenFlagTrue() {
        let vm = AuthViewModel(provider: MockAuthProvider())
        vm.applyForTesting(profile: makeProfile(usernameSet: true), hasSession: true)
        #expect(vm.route == .ready)
    }

    @Test func checkUsernameRejectsBadFormatWithoutHittingProvider() async {
        let vm = AuthViewModel(provider: MockAuthProvider())
        await vm.checkUsername("ab")   // too short
        #expect(vm.usernameStatus == .invalid)
    }

    @Test func checkUsernameReportsTaken() async {
        let mock = MockAuthProvider()
        await mock.setAvailable(false)
        let vm = AuthViewModel(provider: mock)
        await vm.checkUsername("good_name")
        #expect(vm.usernameStatus == .taken)
    }

    @Test func oauthCancelIsNotAnError() async {
        let mock = MockAuthProvider()
        await mock.setError(AuthProviderError.cancelled)
        let vm = AuthViewModel(provider: mock)
        await vm.signInWithGoogle()
        #expect(vm.errorMessage == nil)
    }

    /// Finding 1 (Critical): a device token registered for user A must be
    /// unregistered before the session goes away, because
    /// `unregister_device_token` is a SECURITY DEFINER RPC that resolves
    /// `auth.uid()` — once `provider.signOut()` has torn down the session,
    /// the call can no longer authorize and silently does nothing. So the
    /// ordering (not just "both happened") is the whole point of this test.
    @Test func signOutUnregistersPushBeforeCallingTheProvider() async {
        let mock = MockAuthProvider()
        let order = OrderRecorder()
        await mock.setOnSignOut { await order.record("provider.signOut") }
        let vm = AuthViewModel(provider: mock, willSignOut: { await order.record("willSignOut") })

        await vm.signOut()

        #expect(await order.events == ["willSignOut", "provider.signOut"])
    }

    /// Actor because the closures are `@Sendable` and cross isolation.
    private actor OrderRecorder {
        private(set) var events: [String] = []
        func record(_ label: String) { events.append(label) }
    }
}
