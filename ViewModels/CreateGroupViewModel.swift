import Foundation

@MainActor
@Observable
final class CreateGroupViewModel {
    var name = ""
    var groupDescription = ""
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let service: GroupServicing

    init(service: GroupServicing = GroupService.shared) {
        self.service = service
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        let count = trimmedName.count
        return count >= 1 && count <= 60 && !isSubmitting
    }

    func submit() async -> FellowshipGroup? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let desc = groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let params = CreateGroupParams(name: trimmedName, description: desc.isEmpty ? nil : desc)
            return try await service.createGroup(params)
        } catch {
            errorMessage = PostError.message(for: error)
            return nil
        }
    }
}
