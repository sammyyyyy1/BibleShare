import Testing
import Foundation
@testable import BibleShare

struct BibleServiceTests {

    @Test func formatsSingleVerseLabel() {
        #expect(BibleService.referenceLabel(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9)
                == "Joshua 1:9")
    }

    /// Ranges use an en dash (–), matching the spec's "John 3:16–17".
    @Test func formatsVerseRangeLabel() {
        #expect(BibleService.referenceLabel(book: "John", chapter: 3, verseStart: 16, verseEnd: 17)
                == "John 3:16–17")
    }

    @Test func parsesPassageResponse() throws {
        let json = """
        {"reference":"John 3:16-17","translation_name":"World English Bible",
         "verses":[{"book_name":"John","chapter":3,"verse":16,"text":"For God so loved the world.\\n"},
                   {"book_name":"John","chapter":3,"verse":17,"text":"For God didn't send his Son.\\n"}],
         "text":"For God so loved the world.\\nFor God didn't send his Son.\\n"}
        """.data(using: .utf8)!

        let passage = try BibleService.parse(json, label: "John 3:16–17")
        #expect(passage.referenceLabel == "John 3:16–17")
        // Verse texts are joined and whitespace-normalized — no stray newlines.
        #expect(passage.text == "For God so loved the world. For God didn't send his Son.")
    }

    @Test func parseThrowsNotFoundOnEmptyVerses() {
        let json = #"{"verses":[]}"#.data(using: .utf8)!
        #expect(throws: BibleError.notFound) {
            try BibleService.parse(json, label: "Nope 1:1")
        }
    }
}
