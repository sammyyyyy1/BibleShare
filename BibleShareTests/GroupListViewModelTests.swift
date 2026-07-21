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
    }
}

/// A trivial Error for exercising error paths in ViewModel tests.
enum PostErrorStub: Error { case boom }
