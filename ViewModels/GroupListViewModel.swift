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
    /// Defaults to the real scheduler; tests substitute a recorder so the suite
    /// never touches UNUserNotificationCenter.
    private let scheduleReminders: @Sendable ([FellowshipGroup]) async -> Void

    init(myID: UUID,
         service: GroupServicing = GroupService.shared,
         scheduleReminders: (@Sendable ([FellowshipGroup]) async -> Void)? = nil) {
        self.myID = myID
        self.service = service
        self.scheduleReminders = scheduleReminders
            ?? { await CheckinReminderScheduler.sync(groups: $0) }
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
            // Reminders mirror the group list, so refreshing them here means a
            // changed schedule -- or a group the user left -- cannot strand a
            // stale local notification. sync() replaces this app's own requests
            // wholesale, so calling it on every load is idempotent, not additive.
            await scheduleReminders(groups.map(\.group))
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
