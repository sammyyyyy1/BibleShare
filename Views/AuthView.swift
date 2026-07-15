import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        @Bindable var auth = auth
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 40)

                VStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 44)).foregroundStyle(Theme.indigo)
                    Text("BibleShare").font(Theme.wordmark).foregroundStyle(Theme.ink)
                    Text("Share the Word, together.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }

                VStack(spacing: 10) {
                    SereneTextField(title: "Email", text: $email,
                                    keyboard: .emailAddress, content: .emailAddress)
                    SereneSecureField(title: "Password", text: $password,
                                      content: isSignUp ? .newPassword : .password)
                }

                if let error = auth.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(title: isSignUp ? "Create Account" : "Sign In",
                              isLoading: auth.isLoading) {
                    Task { await submit() }
                }
                .disabled(email.isEmpty || password.isEmpty)

                OrDivider(text: "OR CONTINUE WITH").padding(.vertical, 2)

                VStack(spacing: 8) {
                    SocialButton(label: "Continue with Google",
                                 systemMark: "g.circle.fill", markColor: .blue) {
                        Task { await auth.signInWithGoogle() }
                    }
                    SocialButton(label: "Continue with Discord",
                                 systemMark: "bubble.left.fill", markColor: .indigo) {
                        Task { await auth.signInWithDiscord() }
                    }
                }

                Button(isSignUp ? "Have an account? Sign In" : "New here? Sign Up") {
                    isSignUp.toggle(); auth.errorMessage = nil
                }
                .font(.footnote).foregroundStyle(Theme.indigo)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.cream.ignoresSafeArea())
    }

    private func submit() async {
        if isSignUp {
            await auth.signUpEmail(email: email, password: password)
        } else {
            await auth.signInEmail(email: email, password: password)
        }
    }
}

#Preview {
    AuthView().environment(AuthViewModel(provider: SupabaseService.shared))
}
