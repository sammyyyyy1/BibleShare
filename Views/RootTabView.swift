import SwiftUI

/// The signed-in shell. Home / Groups / Check-in / Alerts / Profile.
struct RootTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppRouter.self) private var router
    /// Hoisted so the Check-in tab's badge count and its list share one fetch.
    @State private var checkInVM = CheckInViewModel()
    /// Hoisted so the Alerts badge and its list share one fetch.
    @State private var notificationsVM = NotificationsViewModel()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            if let userID = auth.profile?.id {
                GroupsView(myID: userID)
                    .tabItem { Label("Groups", systemImage: "person.3.fill") }
                    .tag(AppTab.groups)

                CheckInView(userID: userID, vm: checkInVM)
                    .tabItem { Label("Check-in", systemImage: "checkmark.circle") }
                    .badge(checkInVM.pendingCount)
                    .tag(AppTab.checkIn)

                NotificationsView(vm: notificationsVM)
                    .tabItem { Label("Alerts", systemImage: "bell.fill") }
                    .badge(notificationsVM.unreadCount)
                    .tag(AppTab.alerts)
            }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.indigo)
        .task {
            await checkInVM.load()
            await notificationsVM.load()
        }
    }
}

#Preview {
    RootTabView()
        .environment(AuthViewModel(provider: SupabaseService.shared))
        .environment(AppRouter())
}
