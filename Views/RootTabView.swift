import SwiftUI

/// The signed-in shell. Home / Groups / Check-in / Profile; Plan 6 adds Notifications.
struct RootTabView: View {
    @Environment(AuthViewModel.self) private var auth
    /// Hoisted so the Check-in tab's badge count and its list share one fetch.
    @State private var checkInVM = CheckInViewModel()

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            if let userID = auth.profile?.id {
                GroupsView(myID: userID)
                    .tabItem { Label("Groups", systemImage: "person.3.fill") }

                CheckInView(userID: userID, vm: checkInVM)
                    .tabItem { Label("Check-in", systemImage: "checkmark.circle") }
                    .badge(checkInVM.pendingCount)
            }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.indigo)
        .task { await checkInVM.load() }
    }
}

#Preview {
    RootTabView().environment(AuthViewModel(provider: SupabaseService.shared))
}
