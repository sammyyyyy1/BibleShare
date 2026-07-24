import Testing
import Foundation
@testable import BibleShare

@MainActor
struct CheckInViewModelTests {
    @Test func loadPopulatesTargetsAndClearsError() async {
        let fake = FakeGroupService()
        fake.activeTargets = [CheckinTarget(groupID: UUID(), name: "Daily Crew", windowID: UUID()),
                              CheckinTarget(groupID: UUID(), name: "Second Crew", windowID: UUID())]
        let vm = CheckInViewModel(service: fake)
        vm.errorMessage = "stale"

        await vm.load()

        #expect(vm.targets.count == 2)
        #expect(vm.pendingCount == 2)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test func loadFailureSetsErrorAndKeepsListEmpty() async {
        let fake = FakeGroupService()
        fake.targetsError = PostErrorStub.boom
        let vm = CheckInViewModel(service: fake)

        await vm.load()

        #expect(vm.targets.isEmpty)
        #expect(vm.pendingCount == 0)
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }
}
