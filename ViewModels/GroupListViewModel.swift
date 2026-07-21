import Foundation

@MainActor
@Observable
final class GroupListViewModel {
    private(set) var groups: [GroupListItem] = []
    private(set) var invites: [GroupInviteRow] = []
    private(set) var isLoading = false
    var errorMessage: String?

    let myID: UUID
    private let service: GroupServicing

    init(myID: UUID, service: GroupServicing = GroupService.shared) {
        self.myID = myID
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let groupsTask = service.fetchMyGroups(userID: myID)
            async let invitesTask = service.fetchIncomingInvites(userID: myID)
            groups = try await groupsTask
            invites = try await invitesTask
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func respond(inviteID: UUID, accept: Bool) async {
        do {
            try await service.respondToInvite(inviteID: inviteID, accept: accept)
            await load()
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }
}
