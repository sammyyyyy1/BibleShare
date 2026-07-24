import Testing
import Foundation
@testable import BibleShare

@MainActor
struct CreateGroupViewModelTests {
    @Test func canSubmitRequiresNonEmptyNameWithinLimit() {
        let vm = CreateGroupViewModel(service: FakeGroupService())
        #expect(vm.canSubmit == false)
        vm.name = "   "
        #expect(vm.canSubmit == false)
        vm.name = "Morning Prayer"
        #expect(vm.canSubmit == true)
        vm.name = String(repeating: "x", count: 61)
        #expect(vm.canSubmit == false)
    }

    @Test func submitPassesTrimmedNameAndNilDescription() async {
        let fake = FakeGroupService()
        let vm = CreateGroupViewModel(service: fake)
        vm.name = "  Group A  "
        vm.groupDescription = "   "
        let result = await vm.submit()
        #expect(result != nil)
        #expect(fake.createdParams.first?.name == "Group A")
        #expect(fake.createdParams.first?.description == nil)
    }

    @Test func submitSurfacesError() async {
        let fake = FakeGroupService()
        fake.createError = PostErrorStub.boom
        let vm = CreateGroupViewModel(service: fake)
        vm.name = "Group A"
        let result = await vm.submit()
        #expect(result == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func cadenceNoneSendsNoSchedule() async {
        let fake = FakeGroupService()
        let vm = CreateGroupViewModel(service: fake)
        vm.name = "G"
        _ = await vm.submit()
        let params = fake.createdParams.first
        #expect(params?.cadence == "none")
        #expect(params?.time == nil)
        #expect(params?.weekday == nil)
        #expect(params?.timezone == TimeZone.current.identifier)
    }

    @Test func dailySendsTimeButNoWeekday() async {
        let fake = FakeGroupService()
        let vm = CreateGroupViewModel(service: fake)
        vm.name = "G"
        vm.cadence = .daily
        vm.checkinTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 30))!
        _ = await vm.submit()
        let params = fake.createdParams.first
        #expect(params?.cadence == "daily")
        #expect(params?.time == "09:30:00")
        #expect(params?.weekday == nil)
    }

    @Test func weeklySendsTimeAndWeekday() async {
        let fake = FakeGroupService()
        let vm = CreateGroupViewModel(service: fake)
        vm.name = "G"
        vm.cadence = .weekly
        vm.checkinTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0))!
        vm.weekday = 3
        _ = await vm.submit()
        let params = fake.createdParams.first
        #expect(params?.cadence == "weekly")
        #expect(params?.time == "18:00:00")
        #expect(params?.weekday == 3)
    }
}
