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

/// Params for the `check_in` RPC. Keys mirror the RPC's parameter names.
/// No timeline flag: check-ins never reach the personal timeline (the RPC
/// hard-codes shared_to_timeline = false).
struct CheckInParams: Encodable, Sendable {
    var groupIDs: [UUID]
    var title: String?
    var body: String?
    var verses: [NewVerse]
    var media: [NewMediaItem]
    var tagUserIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case groupIDs = "p_group_ids"
        case title = "p_title"
        case body = "p_body"
        case verses = "p_verses"
        case media = "p_media"
        case tagUserIDs = "p_tag_user_ids"
    }

    // Same lowercasing rationale as CreateEncouragementParams.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groupIDs.map { $0.uuidString.lowercased() }, forKey: .groupIDs)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encode(verses, forKey: .verses)
        try c.encode(media, forKey: .media)
        try c.encode(tagUserIDs, forKey: .tagUserIDs)
    }
}
