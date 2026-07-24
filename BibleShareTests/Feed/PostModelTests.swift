import Testing
import Foundation
@testable import BibleShare

struct PostModelTests {
    /// Decoder matching Supabase's PostgREST timestamps (ISO8601 + fractional seconds).
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "bad date \(s)"))
        }
        return d
    }

    @Test func decodesEncouragement() throws {
        let json = """
        {"id":"99999990-0000-0000-0000-000000000001",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "kind":"encouragement","title":"Be strong","body":"Joshua 1:9",
         "shared_to_timeline":true,"created_at":"2026-07-15T12:00:00.000Z"}
        """.data(using: .utf8)!
        let post = try decoder().decode(Post.self, from: json)
        #expect(post.kind == .encouragement)
        #expect(post.title == "Be strong")
        #expect(post.sharedToTimeline == true)
    }

    @Test func decodesCheckIn() throws {
        let json = """
        {"id":"99999999-0000-0000-0000-0000000000c1",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "kind":"check_in","title":null,"body":null,
         "shared_to_timeline":false,"created_at":"2026-07-15T12:00:00Z"}
        """.data(using: .utf8)!
        let post = try decoder().decode(Post.self, from: json)
        #expect(post.kind == .checkIn)
        #expect(post.title == nil)
        #expect(post.sharedToTimeline == false)
    }
}
