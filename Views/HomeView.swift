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
                Button { showCompose = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.indigo)
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
}

#Preview {
    HomeView().environment(AuthViewModel(provider: SupabaseService.shared))
}
