import Foundation

@MainActor
@Observable
final class CreateGroupViewModel {
    var name = ""
    var groupDescription = ""
    /// Check-in schedule (Plan 5). Weekday uses the Postgres extract(dow)
    /// convention: 0 = Sunday … 6 = Saturday. Timezone is the device's,
    /// shown read-only in the view.
    var cadence: CheckinCadence = .none
    var checkinTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    var weekday = 0
    let timezone = TimeZone.current.identifier
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let service: GroupServicing

    /// Postgres `time` wire format.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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
            let params = CreateGroupParams(
                name: trimmedName,
                description: desc.isEmpty ? nil : desc,
                cadence: cadence.rawValue,
                time: cadence == .none ? nil : Self.timeFormatter.string(from: checkinTime),
                weekday: cadence == .weekly ? weekday : nil,
                timezone: timezone)
            return try await service.createGroup(params)
        } catch {
            errorMessage = PostError.message(for: error)
            return nil
        }
    }
}
