import Testing
import Foundation
@testable import BibleShare

@MainActor
struct ComposeViewModelTests {

    private func makeVM(posts: FakePostService = FakePostService(),
                        uploader: FakeMediaUploader = FakeMediaUploader(),
                        resolver: FakeUsernameResolver = FakeUsernameResolver(),
                        bible: FakeBibleService = FakeBibleService()) -> ComposeViewModel {
        ComposeViewModel(posts: posts, uploader: uploader, resolver: resolver, bible: bible)
    }

    @Test func requiresATitle() {
        let vm = makeVM()
        #expect(vm.canSubmit == false)
        vm.title = "   "
        #expect(vm.canSubmit == false, "whitespace is not a title")
        vm.title = "Be strong"
        #expect(vm.canSubmit == true)
    }

    @Test func trimsTitleAndDropsEmptyBody() async throws {
        let posts = FakePostService()
        let vm = makeVM(posts: posts)
        vm.title = "  Be strong  "
        vm.body = "   "
        _ = await vm.submit(userID: UUID())

        let params = try #require(posts.createdParams.first)
        #expect(params.title == "Be strong")
        #expect(params.body == nil, "a whitespace-only body must send null, not blanks")
    }

    @Test func capsImagesAtFour() {
        let vm = makeVM()
        for _ in 0..<ComposeViewModel.maxImages {
            #expect(vm.canAddImage == true)
            vm.pendingImages.append(ComposeImage(id: UUID(), jpeg: Data([0x1])))
        }
        #expect(vm.canAddImage == false)
    }

    @Test func submitUploadsImagesAndSendsTheirPaths() async throws {
        let posts = FakePostService()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "With photos"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1])),
                            ComposeImage(id: UUID(), jpeg: Data([0x2]))]

        let id = await vm.submit(userID: UUID())
        #expect(id == posts.newPostID)
        #expect(uploader.uploadCount == 2)

        let params = try #require(posts.createdParams.first)
        #expect(params.media.count == 2)
        #expect(params.media.map(\.position) == [0, 1])
        #expect(params.media.allSatisfy { $0.mediaType == .image })
    }

    /// The orphan-free contract from spec §5.1: if the RPC fails after uploads
    /// succeeded, the just-uploaded objects must be deleted.
    @Test func failedSubmitDeletesUploadedImagesAndKeepsDraft() async {
        struct RPCFailure: Error {}
        let posts = FakePostService()
        posts.createError = RPCFailure()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "Doomed"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1]))]

        let id = await vm.submit(userID: UUID())

        #expect(id == nil)
        #expect(uploader.deletedPaths.count == 1, "the orphaned object must be swept")
        #expect(vm.title == "Doomed", "the draft must survive a failed submit")
        #expect(vm.errorMessage != nil)
        #expect(vm.isSubmitting == false)
    }

    @Test func addVerseFetchesSnapshotAndLabel() async throws {
        let bible = FakeBibleService()
        let vm = makeVM(bible: bible)
        await vm.addVerse(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9)

        let verse = try #require(vm.verses.first)
        #expect(verse.referenceLabel == "Joshua 1:9")
        #expect(verse.textSnapshot == "Be strong and courageous.")
        #expect(verse.position == 0)
    }

    @Test func addVerseSurfacesFetchFailureWithoutAddingAnything() async {
        let bible = FakeBibleService()
        bible.error = BibleError.notFound
        let vm = makeVM(bible: bible)
        await vm.addVerse(book: "Nope", chapter: 1, verseStart: 1, verseEnd: 1)

        #expect(vm.verses.isEmpty, "never attach a verse with an empty snapshot")
        #expect(vm.errorMessage != nil)
    }

    @Test func addTagResolvesExactUsername() async throws {
        let resolver = FakeUsernameResolver()
        let bob = try TestDecoder.postgrest().decode(Profile.self, from: """
        {"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob","username_set":true,
         "display_name":null,"avatar_url":null,"bio":null,"created_at":"2026-07-01T12:00:00Z"}
        """.data(using: .utf8)!)
        resolver.profiles["bob"] = bob
        let vm = makeVM(resolver: resolver)

        await vm.addTag(username: "@bob")
        #expect(vm.taggedUsers.map(\.username) == ["bob"])

        await vm.addTag(username: "@bob")
        #expect(vm.taggedUsers.count == 1, "tagging the same user twice is a no-op")

        await vm.addTag(username: "@nobody")
        #expect(vm.taggedUsers.count == 1)
        #expect(vm.errorMessage != nil, "an unknown username is an error, not a silent drop")
    }
}
