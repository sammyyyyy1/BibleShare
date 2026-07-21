import SwiftUI

/// Groups tab: pending invites, then the user's groups, with a create entry.
struct GroupsView: View {
    let myID: UUID

    @State private var vm: GroupListViewModel
    @State private var showCreate = false

    init(myID: UUID, service: GroupServicing = GroupService.shared) {
        self.myID = myID
        _vm = State(initialValue: GroupListViewModel(myID: myID, service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = vm.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    }

                    if !vm.invites.isEmpty {
                        invitesSection
                    }

                    groupsSection
                }
                .padding(16)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .foregroundStyle(Theme.indigo)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showCreate) {
                CreateGroupView { await vm.load() }
            }
        }
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invites").font(.headline).foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                ForEach(vm.invites) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.group?.name ?? "A group")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("from @\(invite.inviter?.username ?? "someone")")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Join") { Task { await vm.respond(inviteID: invite.id, accept: true) } }
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.indigo).clipShape(Capsule())
                        Button("Decline") { Task { await vm.respond(inviteID: invite.id, accept: false) } }
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.danger.opacity(0.1)).clipShape(Capsule())
                    }
                    .padding(.vertical, 10)
                    if invite.id != vm.invites.last?.id { Divider().overlay(Theme.hairline) }
                }
            }
            .padding(.horizontal, 12)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your groups").font(.headline).foregroundStyle(Theme.ink)
            if vm.groups.isEmpty {
                Text("No groups yet — create one with the + button.")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.groups) { item in
                        NavigationLink {
                            GroupTimelineView(group: item.group, myID: myID)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.group.name)
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text("\(item.memberCount) member\(item.memberCount == 1 ? "" : "s")\(item.role == "creator" ? " · creator" : "")")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if item.id != vm.groups.last?.id { Divider().overlay(Theme.hairline) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
            }
        }
    }
}
