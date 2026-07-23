import Foundation

/// Check-in DTOs. `CheckinTarget` decodes the `active_checkin_targets` payload.

/// Row of `active_checkin_targets()`: one of the caller's groups with an open,
/// unanswered check-in window. Drives the Check-in tab + check-in compose.
struct CheckinTarget: Decodable, Identifiable, Hashable, Sendable {
    let groupID: UUID
    let name: String
    let windowID: UUID

    var id: UUID { groupID }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case name
        case windowID = "window_id"
    }
}
