import SwiftUI

struct HomeView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("BibleShare")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                } label: {
                    Circle().fill(Theme.indigo).frame(width: 30, height: 30)
                        .overlay(Text(String(auth.currentUsername?.prefix(1) ?? "?").uppercased())
                            .font(.caption).foregroundStyle(.white))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider().overlay(Theme.hairline)

            // Empty state
            Spacer()
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20).fill(Theme.hairline.opacity(0.6))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "bird").font(.system(size: 28)).foregroundStyle(Theme.indigo))
                Text("Welcome, @\(auth.currentUsername ?? "friend")")
                    .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                Text("Your home feed is empty for now.\nFeatures are coming soon.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            // Tab bar stub (non-functional placeholders)
            HStack {
                tabIcon("house.fill", active: true)
                tabIcon("magnifyingglass", active: false)
                tabIcon("square.and.pencil", active: false)
                tabIcon("person", active: false)
            }
            .padding(.top, 10).padding(.bottom, 4)
            .overlay(Divider().overlay(Theme.hairline), alignment: .top)
        }
        .background(Theme.cream.ignoresSafeArea())
    }

    private func tabIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(active ? Theme.indigo : Theme.muted.opacity(0.5))
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView().environment(AuthViewModel(provider: SupabaseService.shared))
}
