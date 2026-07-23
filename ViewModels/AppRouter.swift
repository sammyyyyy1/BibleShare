import Foundation

enum AppTab: Hashable, Sendable {
    case home, groups, checkIn, alerts, profile
}

/// Tab-level routing for notification taps. Screen-level deep links need a
/// navigation refactor this milestone does not absorb (spec §8.4) — this is
/// the seam that refactor will plug into.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    func select(_ destination: NotificationDestination) {
        switch destination {
        case .post:               selectedTab = .home
        case .group, .invites:    selectedTab = .groups
        case .friends:            selectedTab = .profile
        }
    }
}
