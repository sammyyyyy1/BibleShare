import SwiftUI

/// Friends hub: add by exact username, answer requests, browse the list.
/// Presented as a sheet from HomeView's person tab (mirrors the compose sheet).
struct FriendsView: View {
    @State private var vm: FriendsViewModel
    @State private var addUsername = ""
    @Environment(\.dismiss) private var dismiss

    init(myID: UUID, service: FriendServicing = FriendService.shared) {
        _vm = State(initialValue: FriendsViewModel(myID: myID, service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    addCard

                    if let error = vm.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    }

                    if !vm.incoming.isEmpty {
                        edgeSection("Requests", edges: vm.incoming) { edge in
                            HStack {
                                nameLine(edge.otherParty(myID: vm.myID))
                                Spacer()
                                Button("Accept") {
                                    Task { await vm.respond(requesterID: edge.requesterID, accept: true) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.indigo)
                                .clipShape(Capsule())
                                Button("Decline") {
                                    Task { await vm.respond(requesterID: edge.requesterID, accept: false) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.danger.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }

                    if !vm.outgoing.isEmpty {
                        edgeSection("Sent", edges: vm.outgoing) { edge in
                            HStack {
                                nameLine(edge.otherParty(myID: vm.myID))
                                Spacer()
                                Text("Awaiting response")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    friendsSection
                }
                .padding(16)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Add friend

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a friend").font(.headline).foregroundStyle(Theme.ink)
            SereneTextField(title: "username", text: $addUsername, autocapitalization: .never)
            Text("Enter their exact username.")
                .font(.caption).foregroundStyle(Theme.muted)
            if let status = vm.addStatus {
                Text(status).font(.caption).foregroundStyle(Theme.success)
            }
            if let error = vm.addError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
            PrimaryButton(title: "Send request", isLoading: vm.isAdding) {
                Task {
                    await vm.addFriend(username: addUsername)
                    if vm.addError == nil { addUsername = "" }
                }
            }
            .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty || vm.isAdding)
        }
    }

    // MARK: - Friends list

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friends").font(.headline).foregroundStyle(Theme.ink)
            SereneTextField(title: "Search friends", text: $vm.searchText, autocapitalization: .never)
            if vm.filteredFriends.isEmpty {
                Text(vm.accepted.isEmpty ? "No friends yet — add someone above." : "No matches.")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.filteredFriends) { edge in
                        nameLine(edge.otherParty(myID: vm.myID))
                            .padding(.vertical, 10)
                        if edge.id != vm.filteredFriends.last?.id {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
            }
        }
    }

    // MARK: - Shared rows

    private func edgeSection<Content: View>(_ title: String,
                                            edges: [FriendEdge],
                                            @ViewBuilder row: @escaping (FriendEdge) -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                ForEach(edges) { edge in
                    row(edge).padding(.vertical, 10)
                    if edge.id != edges.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
        }
    }

    private func nameLine(_ profile: Profile?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile?.displayName ?? profile?.username ?? "Unknown")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            if profile?.displayName != nil {
                Text("@\(profile?.username ?? "")")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

#Preview {
    FriendsView(myID: UUID(), service: FriendService.shared)
}
