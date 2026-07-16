import Foundation

struct VersePassage: Hashable, Sendable {
    let referenceLabel: String
    let text: String
}

enum BibleError: Error, Equatable {
    case notFound
    case network
}

protocol BibleFetching: Sendable {
    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage
}

/// Fetches public-domain WEB passages. Per spec §10 the text is snapshotted into
/// post_verses.text_snapshot at compose time, so rendering never depends on this.
actor BibleService: BibleFetching {
    static let shared = BibleService()

    private var cache: [String: VersePassage] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func referenceLabel(book: String, chapter: Int, verseStart: Int, verseEnd: Int) -> String {
        verseEnd > verseStart
            ? "\(book) \(chapter):\(verseStart)–\(verseEnd)"   // en dash
            : "\(book) \(chapter):\(verseStart)"
    }

    private struct APIResponse: Decodable {
        struct Verse: Decodable { let text: String }
        let verses: [Verse]
    }

    static func parse(_ data: Data, label: String) throws -> VersePassage {
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard !decoded.verses.isEmpty else { throw BibleError.notFound }
        let text = decoded.verses
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return VersePassage(referenceLabel: label, text: text)
    }

    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage {
        let label = Self.referenceLabel(book: book, chapter: chapter,
                                        verseStart: verseStart, verseEnd: verseEnd)
        if let hit = cache[label] { return hit }

        let range = verseEnd > verseStart ? "\(verseStart)-\(verseEnd)" : "\(verseStart)"
        var components = URLComponents(string: "https://bible-api.com/")!
        components.path = "/\(book) \(chapter):\(range)"
        components.queryItems = [URLQueryItem(name: "translation", value: "web")]
        guard let url = components.url else { throw BibleError.notFound }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw BibleError.network
        }
        guard let http = response as? HTTPURLResponse else { throw BibleError.network }
        guard http.statusCode == 200 else {
            throw http.statusCode == 404 ? BibleError.notFound : BibleError.network
        }

        let passage = try Self.parse(data, label: label)
        cache[label] = passage
        return passage
    }
}
