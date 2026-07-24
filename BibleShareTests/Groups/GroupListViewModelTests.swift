import Testing
import Foundation
@testable import BibleShare

@MainActor
struct GroupListViewModelTests {
    private let myID = UUID()

    private func listItem(name: String, role: String = "member") -> GroupListItem {
        GroupListItem(role: role,
                      group: FellowshipGroup(id: UUID(), creatorID: UUID(), name: name,
                                             description: nil, checkinCadence: .none, checkinTime: nil,
                                             checkinWeekday: nil, timezone: "America/New_York",
                                             createdAt: Date()),
                      memberCount: 2)
    }

    @Test func loadPopulatesGroupsAndInvites() async {
        let fake = FakeGroupService()
        fake.myGroups = [listItem(name: "Group A"), listItem(name: "Group B")]
        fake.invites = []
        let vm = GroupListViewModel(myID: myID, service: fake)
        await vm.load()
        #expect(vm.groups.count == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadSurfacesError() async {
        let fake = FakeGroupService()
        fake.fetchError = PostErrorStub.boom
        let vm = GroupListViewModel(myID: myID, service: fake)
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test func respondReloads() async {
        let fake = FakeGroupService()
        let vm = GroupListViewModel(myID: myID, service: fake)
        let inviteID = UUID()
        await vm.respond(inviteID: inviteID, accept: true)
        #expect(fake.respondCalls.first?.inviteID == inviteID)
        #expect(fake.respondCalls.first?.accept == true)
        #expect(fake.myGroupsFetchCount >= 1)
        #expect(fake.incomingInvitesFetchCount >= 1)
    }

    @Test func loadSchedulesRemindersForTheLoadedGroups() async {
        let fake = FakeGroupService()
        let group = FellowshipGroup(id: UUID(), creatorID: UUID(), name: "Daily Crew",
                                    description: nil, checkinCadence: .daily,
                                    checkinTime: "08:00:00", checkinWeekday: nil,
                                    timezone: "UTC", createdAt: Date())
        fake.myGroups = [GroupListItem(role: "creator", group: group, memberCount: 2)]
        let scheduled = Scheduled()
        let vm = GroupListViewModel(myID: UUID(), service: fake,
                                    scheduleReminders: { await scheduled.record($0) })

        await vm.load()

        #expect(await scheduled.groups.map(\.id) == [group.id])
    }

    /// Actor because the closure is `@Sendable` and crosses isolation.
    private actor Scheduled {
        var groups: [FellowshipGroup] = []
        func record(_ g: [FellowshipGroup]) { groups = g }
    }
}

/// A trivial Error for exercising error paths in ViewModel tests.
enum PostErrorStub: Error { case boom }
