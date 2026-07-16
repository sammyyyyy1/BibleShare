import Testing
import Foundation
@testable import BibleShare

struct FeedModelTests {

    /// The full embedded payload PostgREST returns for the timeline query.
    @Test func decodesFullFeedItem() throws {
        let json = """
        {"id":"99999990-0000-0000-0000-000000000001",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "title":"Be strong","body":"Joshua reminded me.",
         "created_at":"2026-07-16T12:00:00.000Z",
         "author":{"id":"aaaaaaaa-0000-0000-0000-000000000001","username":"alice",
                   "username_set":true,"display_name":"Alice","avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"},
         "post_verses":[
           {"id":"33333333-0000-0000-0000-0000000000cc","post_id":"99999990-0000-0000-0000-000000000001",
            "translation":"WEB","book":"Joshua","chapter":1,"verse_start":9,"verse_end":9,
            "reference_label":"Joshua 1:9","text_snapshot":"Be strong and courageous.","position":1},
           {"id":"33333333-0000-0000-0000-0000000000cd","post_id":"99999990-0000-0000-0000-000000000001",
            "translation":"WEB","book":"John","chapter":3,"verse_start":16,"verse_end":17,
            "reference_label":"John 3:16–17","text_snapshot":"For God so loved...","position":0}],
         "post_media":[
           {"id":"44444444-0000-0000-0000-0000000000dd","post_id":"99999990-0000-0000-0000-000000000001",
            "media_type":"image","url":"aaaaaaaa-0000-0000-0000-000000000001/pic.jpg",
            "thumbnail_url":null,"title":null,"description":null,"position":0}],
         "post_tags":[
           {"post_id":"99999990-0000-0000-0000-000000000001",
            "tagged_user_id":"bbbbbbbb-0000-0000-0000-000000000002",
            "created_at":"2026-07-16T12:00:00Z",
            "profiles":{"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob",
                        "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                        "created_at":"2026-07-01T12:00:00Z"}}],
         "likes":[{"count":3}],
         "comments":[{"count":1}]}
        """.data(using: .utf8)!

        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.title == "Be strong")
        #expect(item.author?.username == "alice")
        #expect(item.likeCount == 3)
        #expect(item.commentCount == 1)
        #expect(item.isLiked == false)             // client-side, defaults false
        #expect(item.media.count == 1)
        #expect(item.tags.first?.profile?.username == "bob")
        // Verses arrive out of order and must be sorted by `position`.
        #expect(item.verses.map(\.referenceLabel) == ["John 3:16–17", "Joshua 1:9"])
    }

    /// A bare post: no body, no attachments, zero counts. PostgREST returns []
    /// for empty embeds, so nothing may be force-unwrapped.
    @Test func decodesBareFeedItem() throws {
        let json = """
        {"id":"99999990-0000-0000-0000-000000000009",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "title":"Just a title","body":null,
         "created_at":"2026-07-16T12:00:00Z",
         "author":{"id":"aaaaaaaa-0000-0000-0000-000000000001","username":"alice",
                   "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"},
         "post_verses":[],"post_media":[],"post_tags":[],
         "likes":[],"comments":[]}
        """.data(using: .utf8)!

        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.body == nil)
        #expect(item.verses.isEmpty)
        #expect(item.likeCount == 0)
        #expect(item.commentCount == 0)
    }

    @Test func decodesCommentItem() throws {
        let json = """
        {"id":"55555555-0000-0000-0000-0000000000ee",
         "post_id":"99999990-0000-0000-0000-000000000001",
         "author_id":"bbbbbbbb-0000-0000-0000-000000000002",
         "content":"Amen.","created_at":"2026-07-16T12:30:00Z",
         "author":{"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob",
                   "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"}}
        """.data(using: .utf8)!

        let c = try TestDecoder.postgrest().decode(CommentItem.self, from: json)
        #expect(c.content == "Amen.")
        #expect(c.author?.username == "bob")
    }

    /// The RPC params must serialize to the exact parameter names the SQL declares.
    @Test func encodesCreateEncouragementParams() throws {
        let params = CreateEncouragementParams(
            title: "Be strong",
            body: nil,
            sharedToTimeline: true,
            verses: [NewVerse(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9,
                              referenceLabel: "Joshua 1:9", textSnapshot: "Be strong.", position: 0)],
            media: [NewMediaItem(mediaType: .image, url: "uid/pic.jpg", position: 0)],
            tagUserIDs: [UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!]
        )
        let data = try JSONEncoder().encode(params)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(obj["p_title"] as? String == "Be strong")
        #expect(obj["p_shared_to_timeline"] as? Bool == true)
        #expect((obj["p_verses"] as? [[String: Any]])?.first?["reference_label"] as? String == "Joshua 1:9")
        #expect((obj["p_media"] as? [[String: Any]])?.first?["media_type"] as? String == "image")
        #expect((obj["p_tag_user_ids"] as? [String])?.count == 1)
    }
}
