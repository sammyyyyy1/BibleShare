import SwiftUI

/// Sign-in / sign-up screen. Serves as the working end-to-end example
/// against the real Supabase project.
struct AuthView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    private enum Mode {
        case signIn, signUp

        var title: String { self == .signIn ? "Sign In" : "Sign Up" }
        var togglePrompt: String {
            self == .signIn ? "Don't have an account? Sign Up" : "Have an account? Sign In"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "book.pages")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("BibleShare")
                    .font(.largeTitle.bold())

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                }
                .textFieldStyle(.roundedBorder)

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(mode.title)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

                Button(mode.togglePrompt) {
                    mode = (mode == .signIn) ? .signUp : .signIn
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() async {
        switch mode {
        case .signIn:
            await auth.signInEmail(email: email, password: password)
        case .signUp:
            await auth.signUpEmail(email: email, password: password)
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthViewModel())
}
