import Testing
import Foundation
import Supabase
@testable import BibleShare

/// Direct unit tests for `PostService.deletePost`'s storage-before-row-delete
/// guarantee. Every other test in this suite (`TimelineViewModelTests`) only
/// exercises this behaviour through `FakePostService`, which records calls
/// unconditionally and never runs `PostService`'s real ordering/propagation
/// logic — so a regression that reversed the order, or swallowed a storage
/// failure with `try?`, would pass the entire suite silently.
///
/// `PostService` normally talks to Supabase's PostgREST client for the row
/// delete, which requires a reachable network. To test the ordering without
/// a network dependency, `PostService` exposes an additive `deleteRow` seam
/// (defaulted to `nil`) that a test can substitute for the real
/// `client.from("posts").delete()...execute()` call — this proves the logic
/// in `deletePost` itself, not PostgREST. Real callers (`PostService.shared`
/// and any call site omitting the parameter) are unaffected: `deletePost`'s
/// signature and behaviour are unchanged.
/// A plain `var` captured by an `@Sendable` closure fails Swift 6's strict
/// concurrency check even though these tests only ever call `deletePost`
/// sequentially and `await` its result before reading the recorder. This
/// reference-type box is the minimal way to record calls made from inside
/// `PostService`'s `deleteRow` / `MediaUploading` closures.
private final class Recorder<T>: @unchecked Sendable {
    private(set) var values: [T] = []
    func record(_ value: T) { values.append(value) }
}

@Suite struct PostServiceTests {

    /// Any valid client works here — the test never lets a code path reach
    /// the network, since `deleteRow` is swapped for a fake and `imagePaths`
    /// tests use `FakeMediaUploader`.
    private static var dummyClient: SupabaseClient {
        SupabaseClient(supabaseURL: URL(string: "https://example.invalid")!, supabaseKey: "test-key")
    }

    @Test func deletePostSweepsStorageWithTheExactPathsBeforeDeletingTheRow() async throws {
        let media = FakeMediaUploader()
        let id = UUID()
        let paths = ["someuid/a.jpg", "someuid/b.jpg"]

        // A shared event timeline: both the storage delete and the row
        // delete record into it, so we can assert the actual order, not
        // just that both eventually happened.
        let events = Recorder<String>()
        media.onDelete = { events.record("storage") }
        let sut = PostService(client: Self.dummyClient, media: media) { _ in
            events.record("row")
        }

        try await sut.deletePost(id: id, imagePaths: paths)

        #expect(media.deletedPaths == paths, "storage must be swept with exactly the paths passed in")
        #expect(events.values == ["storage", "row"], "the row delete must fire only after storage has been swept")
    }

    @Test func throwingStorageSweepBlocksTheRowDeleteEntirely() async {
        struct Boom: Error {}
        let media = FakeMediaUploader()
        media.deleteError = Boom()
        let rowDeleteCalls = Recorder<UUID>()
        let sut = PostService(client: Self.dummyClient, media: media) { id in
            rowDeleteCalls.record(id)
        }

        await #expect(throws: Boom.self) {
            try await sut.deletePost(id: UUID(), imagePaths: ["someuid/a.jpg"])
        }

        #expect(rowDeleteCalls.values.isEmpty, "a failed storage sweep must leave the row (and its images) intact for retry")
    }

    @Test func emptyImagePathsSkipsTheStorageCallEntirely() async throws {
        let media = FakeMediaUploader()
        let id = UUID()
        let rowDeleteCalls = Recorder<UUID>()
        let sut = PostService(client: Self.dummyClient, media: media) { id in
            rowDeleteCalls.record(id)
        }

        try await sut.deletePost(id: id, imagePaths: [])

        #expect(media.deleteCallCount == 0, "an image-less post must never call media.delete")
        #expect(rowDeleteCalls.values == [id], "the row must still be deleted when there are no images to sweep")
    }
}
