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
        #expect(uploader.deletedPaths.isEmpty, "a successful submit must never sweep the images the new post references")
    }

    @Test func submitPositionsLinksAfterImages() async throws {
        let posts = FakePostService()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "Photos and links"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1])),
                            ComposeImage(id: UUID(), jpeg: Data([0x2]))]
        vm.addLink(url: "https://example.com/a", title: "A")
        vm.addLink(url: "https://example.com/b", title: "B")

        let id = await vm.submit(userID: UUID())
        #expect(id == posts.newPostID)

        let params = try #require(posts.createdParams.first)
        #expect(params.media.count == 4)

        let images = params.media.filter { $0.mediaType == .image }
        #expect(images.map(\.position).sorted() == [0, 1])

        let linkItems = params.media.filter { $0.mediaType == .link }
        #expect(linkItems.map(\.position) == [2, 3])
        #expect(linkItems.map(\.url) == ["https://example.com/a", "https://example.com/b"])
    }

    @Test func submitPositionsLinksFromZeroWhenNoImages() async throws {
        let posts = FakePostService()
        let vm = makeVM(posts: posts)
        vm.title = "Links only"
        vm.addLink(url: "https://example.com/a", title: "A")
        vm.addLink(url: "https://example.com/b", title: "B")

        _ = await vm.submit(userID: UUID())

        let params = try #require(posts.createdParams.first)
        let linkItems = params.media.filter { $0.mediaType == .link }
        #expect(linkItems.map(\.position) == [0, 1])
    }

    @Test func cannotSubmitWithMoreThanMaxImages() async {
        let posts = FakePostService()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "Too many photos"
        for _ in 0..<(ComposeViewModel.maxImages + 1) {
            vm.pendingImages.append(ComposeImage(id: UUID(), jpeg: Data([0x1])))
        }

        #expect(vm.canSubmit == false)

        let id = await vm.submit(userID: UUID())
        #expect(id == nil)
        #expect(posts.createdParams.isEmpty)
        #expect(uploader.uploadCount == 0)
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

    /// Reviewer-flagged gap: `failedSubmitDeletesUploadedImagesAndKeepsDraft` only
    /// covers the sweep succeeding. When BOTH the RPC and the compensating
    /// delete fail, the sweep failure must be logged (not asserted here — it's
    /// not observable from a unit test) but never surfacer to the user in place
    /// of the original error, and the function must not throw up the call stack.
    @Test func failedSubmitLogsWhenTheCompensatingSweepAlsoFails() async {
        // Distinct `description`s so each maps to a distinct PostError message —
        // this lets the test prove which error the user actually sees, rather
        // than both errors falling into the same generic fallback string.
        struct RPCFailure: Error, CustomStringConvertible {
            var description: String { "title is required" }
        }
        struct SweepFailure: Error, CustomStringConvertible {
            var description: String { "own storage folder" }
        }
        let posts = FakePostService()
        posts.createError = RPCFailure()
        let uploader = FakeMediaUploader()
        uploader.deleteError = SweepFailure()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "Doomed twice"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1]))]

        let id = await vm.submit(userID: UUID())

        #expect(id == nil)
        #expect(uploader.deleteCallCount == 1, "the sweep must still be attempted even though it will fail")
        #expect(uploader.deletedPaths.isEmpty, "a failed sweep must not record paths as deleted")
        #expect(vm.title == "Doomed twice", "the draft must survive even a doubly-failed submit")
        #expect(vm.errorMessage == PostError.message(for: RPCFailure()),
                "the user-facing error must reflect the ORIGINAL create failure")
        #expect(vm.errorMessage != PostError.message(for: SweepFailure()),
                "the sweep failure must never override the original error shown to the user")
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

    @MainActor
    @Test func cannotSubmitWithNoDestination() {
        let vm = ComposeViewModel(posts: FakePostService(), uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        vm.title = "Hello"
        vm.sharedToTimeline = false
        #expect(vm.canSubmit == false)          // no timeline, no group
        vm.selectedGroupIDs = [UUID()]
        #expect(vm.canSubmit == true)           // a group is a destination
    }

    @MainActor
    @Test func submitPassesSelectedGroupIDs() async {
        let fakePosts = FakePostService()
        let vm = ComposeViewModel(posts: fakePosts, uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        let g = UUID()
        vm.title = "Hello"
        vm.sharedToTimeline = false
        vm.selectedGroupIDs = [g]
        _ = await vm.submit(userID: UUID())
        #expect(fakePosts.createdParams.first?.groupIDs == [g])
        #expect(fakePosts.createdParams.first?.sharedToTimeline == false)
    }

    @MainActor
    @Test func loadGroupsPopulatesMyGroups() async {
        let fakeGroups = FakeGroupService()
        fakeGroups.myGroups = [GroupListItem(role: "member",
            group: FellowshipGroup(id: UUID(), creatorID: UUID(), name: "G", description: nil,
                                   checkinCadence: .none, checkinTime: nil, checkinWeekday: nil,
                                   timezone: "America/New_York", createdAt: Date()),
            memberCount: 1)]
        let vm = ComposeViewModel(posts: FakePostService(), uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: fakeGroups)
        await vm.loadGroups(userID: UUID())
        #expect(vm.myGroups.count == 1)
    }

    @MainActor
    @Test func preselectSelectsGroup() {
        let vm = ComposeViewModel(posts: FakePostService(), uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        let g = UUID()
        vm.preselect(groupID: g)
        #expect(vm.selectedGroupIDs.contains(g))
    }

    @MainActor
    @Test func checkInModeRequiresATargetButNoTitle() {
        let vm = ComposeViewModel(mode: .checkIn,
                                  posts: FakePostService(), uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        #expect(vm.canSubmit == false)          // no target selected
        vm.title = "A title changes nothing"
        #expect(vm.canSubmit == false)          // still needs a target
        vm.title = ""
        vm.selectedGroupIDs = [UUID()]
        #expect(vm.canSubmit == true)           // title is optional in check-in mode
    }

    @MainActor
    @Test func checkInModeSubmitRoutesToCheckInRPC() async throws {
        let fakePosts = FakePostService()
        let vm = ComposeViewModel(mode: .checkIn,
                                  posts: fakePosts, uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        let g = UUID()
        vm.selectedGroupIDs = [g]

        let id = await vm.submit(userID: UUID())

        #expect(id == fakePosts.newCheckInPostID)
        #expect(fakePosts.createdParams.isEmpty, "check-in mode must not call createEncouragement")
        let params = try #require(fakePosts.checkInParams.first)
        #expect(params.groupIDs == [g])
        #expect(params.title == nil, "a blank title stays nil for check-ins")
    }

    @MainActor
    @Test func checkInModeSubmitSendsTrimmedTitleWhenProvided() async throws {
        let fakePosts = FakePostService()
        let vm = ComposeViewModel(mode: .checkIn,
                                  posts: fakePosts, uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: FakeGroupService())
        vm.selectedGroupIDs = [UUID()]
        vm.title = "  Doing well  "

        _ = await vm.submit(userID: UUID())

        #expect(fakePosts.checkInParams.first?.title == "Doing well")
    }

    @MainActor
    @Test func loadCheckinTargetsPopulatesOnSuccessAndIgnoresFailure() async {
        let fakeGroups = FakeGroupService()
        fakeGroups.activeTargets = [CheckinTarget(groupID: UUID(), name: "Daily Crew", windowID: UUID())]
        let vm = ComposeViewModel(mode: .checkIn,
                                  posts: FakePostService(), uploader: FakeMediaUploader(),
                                  resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                  groups: fakeGroups)
        await vm.loadCheckinTargets()
        #expect(vm.checkinTargets.count == 1)

        let failingGroups = FakeGroupService()
        failingGroups.targetsError = PostErrorStub.boom
        let vm2 = ComposeViewModel(mode: .checkIn,
                                   posts: FakePostService(), uploader: FakeMediaUploader(),
                                   resolver: FakeUsernameResolver(), bible: FakeBibleService(),
                                   groups: failingGroups)
        await vm2.loadCheckinTargets()
        #expect(vm2.checkinTargets.isEmpty, "a failed targets load leaves the list empty, no error surfaced")
        #expect(vm2.errorMessage == nil)
    }
}
