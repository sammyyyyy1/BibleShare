import SwiftUI

/// Profile tab: the signed-in user's identity, a way into Friends, and sign-out.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var showFriends = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Circle().fill(Theme.indigo).frame(width: 72, height: 72)
                        .overlay(Text(String(auth.currentUsername?.prefix(1) ?? "?").uppercased())
                            .font(.title2).foregroundStyle(.white))
                        .padding(.top, 24)

                    VStack(spacing: 4) {
                        Text(auth.profile?.displayName ?? auth.currentUsername ?? "You")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let username = auth.currentUsername {
                            Text("@\(username)").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }

                    VStack(spacing: 0) {
                        Button { showFriends = true } label: {
                            HStack {
                                Label("Friends", systemImage: "person.2")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))

                    Button(role: .destructive) { Task { await auth.signOut() } } label: {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(14)
                    .background(Theme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))

                    Spacer()
                }
                .padding(20)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFriends) {
                if let userID = auth.profile?.id {
                    FriendsView(myID: userID)
                }
            }
        }
    }
}
