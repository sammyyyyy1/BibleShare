import Testing
import Foundation
@testable import BibleShare

@MainActor
struct AppRouterTests {
    @Test func postDestinationSelectsHome() {
        let router = AppRouter()
        router.selectedTab = .alerts
        router.select(.post(UUID()))
        #expect(router.selectedTab == .home)
    }

    @Test func groupAndInviteDestinationsSelectGroups() {
        let router = AppRouter()
        router.select(.group(UUID()))
        #expect(router.selectedTab == .groups)
        router.selectedTab = .alerts
        router.select(.invites)
        #expect(router.selectedTab == .groups)
    }

    /// FriendsView is a sheet inside ProfileView, so Profile is as deep as
    /// tab-level routing can go.
    @Test func friendsDestinationSelectsProfile() {
        let router = AppRouter()
        router.select(.friends)
        #expect(router.selectedTab == .profile)
    }
}
