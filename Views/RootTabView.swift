import SwiftUI

/// The signed-in shell. Three live tabs; Plans 5–6 add Check-in and Notifications.
struct RootTabView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            if let userID = auth.profile?.id {
                GroupsView(myID: userID)
                    .tabItem { Label("Groups", systemImage: "person.3.fill") }
            }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.indigo)
    }
}

#Preview {
    RootTabView().environment(AuthViewModel(provider: SupabaseService.shared))
}
