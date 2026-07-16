import SwiftUI

struct HomeView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var showCompose = false
    /// Bumped after a successful post to force TimelineView to reload.
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
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

            if let userID = auth.profile?.id {
                TimelineView(userID: userID)
                    .id(reloadToken)
            } else {
                Spacer()
                ProgressView().tint(Theme.indigo)
                Spacer()
            }

            HStack {
                tabIcon("house.fill", active: true) {}
                tabIcon("magnifyingglass", active: false) {}
                tabIcon("square.and.pencil", active: false) { showCompose = true }
                tabIcon("person", active: false) {}
            }
            .padding(.top, 10).padding(.bottom, 4)
            .overlay(Divider().overlay(Theme.hairline), alignment: .top)
        }
        .background(Theme.cream.ignoresSafeArea())
        .sheet(isPresented: $showCompose) {
            if let userID = auth.profile?.id {
                ComposeEncouragementView(userID: userID) { _ in
                    reloadToken = UUID()   // refetch so the new post appears with its author + counts
                }
            }
        }
    }

    private func tabIcon(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundStyle(active ? Theme.indigo : Theme.muted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView().environment(AuthViewModel(provider: SupabaseService.shared))
}
