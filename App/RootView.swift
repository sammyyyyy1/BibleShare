import SwiftUI

struct RootView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        Group {
            switch auth.route {
            case .signedOut:     AuthView()
            case .needsUsername: UsernameSetupView()
            case .ready:         HomeView()
            }
        }
        .animation(.default, value: auth.route)
        .onOpenURL { url in
            // Email-confirmation / OAuth deep links (OAuth web flow is also
            // captured by ASWebAuthenticationSession directly).
            Task { try? await SupabaseService.shared.client.auth.session(from: url) }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthViewModel())
}
