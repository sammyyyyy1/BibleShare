import SwiftUI

/// A single group's timeline + members. Creator sees an invite field; everyone
/// sees a "Post here" button that opens compose pre-selecting this group.
struct GroupTimelineView: View {
    let group: FellowshipGroup
    let myID: UUID

    @State private var vm: GroupTimelineViewModel
    @State private var showCompose = false
    @State private var showMembers = false
    @State private var inviteUsername = ""
    @State private var commentingOn: FeedItem?

    init(group: FellowshipGroup, myID: UUID, service: GroupServicing = GroupService.shared) {
        self.group = group
        self.myID = myID
        _vm = State(initialValue: GroupTimelineViewModel(groupID: group.id, myID: myID, groupService: service))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let error = vm.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                }

                if vm.isCreator { inviteCard }

                Button { showCompose = true } label: {
                    Label("Post here", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.indigo).clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                }

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView().tint(Theme.indigo).frame(maxWidth: .infinity).padding(.top, 30)
                } else if vm.items.isEmpty {
                    Text("No posts in this group yet.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }

                ForEach(vm.items) { item in
                    PostCell(
                        item: item,
                        isMine: item.authorID == myID,
                        onLike: { Task { await vm.toggleLike(itemID: item.id) } },
                        onComment: { commentingOn = item },
                        onDelete: { Task { await vm.delete(itemID: item.id) } }
                    )
                    .onAppear {
                        if item.id == vm.items.last?.id { Task { await vm.loadMore() } }
                    }
                }

                if vm.isLoadingMore {
                    ProgressView().tint(Theme.indigo).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .padding(16)
        }
        .background(Theme.cream)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showMembers = true } label: { Image(systemName: "person.3") }
                    .foregroundStyle(Theme.indigo)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showCompose) {
            ComposeEncouragementView(userID: myID, preselectedGroupID: group.id) { _ in
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showMembers) { membersSheet }
        .sheet(item: $commentingOn) { item in
            CommentsView(postID: item.id, userID: myID)
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite someone").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack {
                SereneTextField(title: "username", text: $inviteUsername, autocapitalization: .never)
                Button("Invite") {
                    Task {
                        await vm.invite(username: inviteUsername)
                        if vm.inviteError == nil { inviteUsername = "" }
                    }
                }
                .foregroundStyle(Theme.indigo)
                .disabled(inviteUsername.trimmingCharacters(in: .whitespaces).isEmpty || vm.isInviting)
            }
            if let status = vm.inviteStatus { Text(status).font(.caption).foregroundStyle(Theme.success) }
            if let error = vm.inviteError { Text(error).font(.caption).foregroundStyle(Theme.danger) }
        }
        .padding(12)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
    }

    private var membersSheet: some View {
        NavigationStack {
            List(vm.members) { member in
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.profile?.displayName ?? member.profile?.username ?? "Unknown")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("@\(member.profile?.username ?? "")\(member.role == "creator" ? " · creator" : "")")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.cream)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
