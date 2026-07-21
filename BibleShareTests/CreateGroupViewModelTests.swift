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
}
