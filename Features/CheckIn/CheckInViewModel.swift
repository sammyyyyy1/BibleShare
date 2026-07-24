import Foundation

/// State for the Check-in tab: the caller's groups with an open, unanswered
/// check-in window. Hoisted into RootTabView so the tab badge and the list
/// share one fetch.
@MainActor
@Observable
final class CheckInViewModel {
    private(set) var targets: [CheckinTarget] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: GroupServicing

    init(service: GroupServicing = GroupService.shared) {
        self.service = service
    }

    var pendingCount: Int { targets.count }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            targets = try await service.fetchActiveCheckinTargets()
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }
}
