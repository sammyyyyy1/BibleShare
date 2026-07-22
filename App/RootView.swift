import SwiftUI
import os

struct RootView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        Group {
            switch auth.route {
            case .signedOut:     AuthView()
            case .needsUsername: UsernameSetupView()
            case .ready:         RootTabView()
            }
        }
        .animation(.default, value: auth.route)
        .onOpenURL { url in
            // Email-confirmation / OAuth deep links (OAuth web flow is also
            // captured by ASWebAuthenticationSession directly).
            // A silent `try?` here makes a failed confirmation indistinguishable
            // from one that never arrived. Log the error only — the URL carries
            // the session token, so it never goes to the log.
            Task {
                do {
                    try await SupabaseService.shared.client.auth.session(from: url)
                } catch {
                    Logger(subsystem: "com.bibleshare.app", category: "deep-link")
                        .error("Failed to exchange a deep link for a session: \(error)")
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthViewModel())
}
