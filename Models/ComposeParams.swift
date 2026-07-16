import Foundation

/// Write-side DTOs. Keys mirror `public.create_encouragement`'s parameter names
/// and the child tables' column names exactly — see
/// supabase/migrations/20260716010100_create_encouragement_rpc.sql

struct NewVerse: Encodable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var translation: String = "WEB"
    var book: String
    var chapter: Int
    var verseStart: Int
    var verseEnd: Int
    var referenceLabel: String
    var textSnapshot: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case translation, book, chapter, position
        case verseStart = "verse_start"
        case verseEnd = "verse_end"
        case referenceLabel = "reference_label"
        case textSnapshot = "text_snapshot"
    }
}

struct NewMediaItem: Encodable, Hashable, Sendable {
    var mediaType: MediaType
    var url: String
    var thumbnailURL: String?
    var title: String?
    var description: String?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case url, title, description, position
        case mediaType = "media_type"
        case thumbnailURL = "thumbnail_url"
    }
}

struct CreateEncouragementParams: Encodable, Sendable {
    var title: String
    var body: String?
    var sharedToTimeline: Bool
    var verses: [NewVerse]
    var media: [NewMediaItem]
    var tagUserIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case title = "p_title"
        case body = "p_body"
        case sharedToTimeline = "p_shared_to_timeline"
        case verses = "p_verses"
        case media = "p_media"
        case tagUserIDs = "p_tag_user_ids"
    }
}
