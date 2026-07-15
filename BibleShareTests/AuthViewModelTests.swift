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
}
