import SwiftUI

/// Root view that switches between the auth flow and the signed-in experience.
struct RootView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        Group {
            switch auth.session {
            case .some:
                SignedInPlaceholderView()
            case .none:
                AuthView()
            }
        }
        .animation(.default, value: auth.session != nil)
    }
}

/// Temporary placeholder shown after a successful sign-in.
private struct SignedInPlaceholderView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "book.pages")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Welcome to BibleShare")
                    .font(.title.bold())
                if let email = auth.currentUserEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Sign Out") {
                    Task { await auth.signOut() }
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

#Preview {
    RootView()
        .environment(AuthViewModel())
}
