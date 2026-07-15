import SwiftUI

struct UsernameSetupView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a username")
                .font(.system(.title, design: .serif).weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("This is how others find and mention you. Choose well.")
                .font(.subheadline).foregroundStyle(Theme.muted)

            HStack(spacing: 2) {
                Text("@").foregroundStyle(Theme.muted)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                statusIcon
            }
            .padding(12)
            .background(Theme.field)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(borderColor))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .onChange(of: username) { _, newValue in auth.usernameChanged(newValue) }

            statusText
            Text("3–20 chars · letters, numbers, underscore")
                .font(.caption2).foregroundStyle(Theme.muted)

            PrimaryButton(title: "Continue", isLoading: auth.isLoading) {
                Task { await auth.submitUsername(username) }
            }
            .disabled(auth.usernameStatus != .available)
            .padding(.top, 6)

            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }

            Spacer()
            signedInFooter
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cream.ignoresSafeArea())
    }

    @ViewBuilder private var statusIcon: some View {
        switch auth.usernameStatus {
        case .checking: ProgressView()
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case .taken, .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var statusText: some View {
        switch auth.usernameStatus {
        case .available: Text("@\(username) is available").font(.caption).foregroundStyle(Theme.success)
        case .taken:     Text("That username is taken").font(.caption).foregroundStyle(Theme.danger)
        case .invalid:   Text("Use 3–20 letters, numbers, or _").font(.caption).foregroundStyle(Theme.danger)
        default:         Color.clear.frame(height: 1)
        }
    }

    private var borderColor: Color {
        switch auth.usernameStatus {
        case .available: Theme.success
        case .taken, .invalid: Theme.danger
        default: Theme.hairline
        }
    }

    private var signedInFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.indigo).frame(width: 26, height: 26)
                .overlay(Text(String(auth.currentUserEmail?.prefix(1) ?? "?").uppercased())
                    .font(.caption2).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text("Signed in as").font(.caption2).foregroundStyle(Theme.muted)
                Text(auth.currentUserEmail ?? "—").font(.caption).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button("Sign out") { Task { await auth.signOut() } }
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(11)
        .background(Theme.hairline.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

#Preview {
    UsernameSetupView().environment(AuthViewModel(provider: SupabaseService.shared))
}
