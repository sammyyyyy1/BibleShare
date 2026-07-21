import SwiftUI

/// The Check-in tab: groups awaiting the caller's check-in, plus the compose
/// entry in check-in mode. The ViewModel comes from RootTabView (shared with
/// the tab badge).
struct CheckInView: View {
    let userID: UUID
    let vm: CheckInViewModel

    @State private var showCompose = false

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cream.ignoresSafeArea())
                .navigationTitle("Check-in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showCompose = true } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.indigo)
                        }
                        .disabled(vm.targets.isEmpty)
                    }
                }
                .task { await vm.load() }
                .sheet(isPresented: $showCompose) {
                    ComposeEncouragementView(userID: userID, mode: .checkIn) { _ in
                        Task { await vm.load() }   // answered groups drop off
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 10) {
            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }

            if vm.isLoading && vm.targets.isEmpty {
                ProgressView().tint(Theme.indigo)
            } else if vm.targets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.muted)
                    Text(vm.errorMessage != nil ? "Couldn't load check-ins." : "No open check-ins right now.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            } else {
                List(vm.targets) { target in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Awaiting your check-in")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Check in") { showCompose = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                    .listRowBackground(Theme.field)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await vm.load() }
            }
        }
    }
}

#Preview {
    CheckInView(userID: UUID(), vm: CheckInViewModel())
}
