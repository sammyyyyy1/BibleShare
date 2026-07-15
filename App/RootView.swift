import OSLog
import SwiftUI

private let deepLinkLog = Logger(subsystem: "BibleShare", category: "deep-link")

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
            Task {
                do {
                    try await SupabaseService.shared.client.auth.session(from: url)
                } catch {
                    deepLinkLog.error("Failed to exchange deep link \(url, privacy: .public): \(error, privacy: .public)")
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthViewModel())
}
