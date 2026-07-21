import Testing
import Foundation
@testable import BibleShare

@MainActor
struct GroupTimelineViewModelTests {
    private let groupID = UUID()
    private let myID = UUID()

    @Test func loadFetchesPostsMembersAndLikeState() async throws {
        let fakeGroup = FakeGroupService()
        let liked = UUID()
        fakeGroup.timeline = [try FeedItemFactory.make(id: liked, likeCount: 1),
                              try FeedItemFactory.make()]
        fakeGroup.members = [GroupMemberRow(userID: myID, role: "creator", profile: nil)]
        let fakeFeed = FakeFeedService()
        fakeFeed.liked = [liked]
        let vm = GroupTimelineViewModel(groupID: groupID, myID: myID,
                                        groupService: fakeGroup, feed: fakeFeed, posts: FakePostService())
        await vm.load()
        #expect(vm.items.count == 2)
        #expect(vm.items.first(where: { $0.id == liked })?.isLiked == true)
        #expect(vm.isCreator == true)
    }

    @Test func isCreatorFalseForPlainMember() async {
        let fakeGroup = FakeGroupService()
        fakeGroup.members = [GroupMemberRow(userID: myID, role: "member", profile: nil)]
        let vm = GroupTimelineViewModel(groupID: groupID, myID: myID,
                                        groupService: fakeGroup, feed: FakeFeedService(), posts: FakePostService())
        await vm.load()
        #expect(vm.isCreator == false)
    }

    @Test func toggleLikeIsOptimisticAndCallsService() async throws {
        let fakeGroup = FakeGroupService()
        let post = try FeedItemFactory.make(likeCount: 0, isLiked: false)
        fakeGroup.timeline = [post]
        let fakePosts = FakePostService()
        let vm = GroupTimelineViewModel(groupID: groupID, myID: myID,
                                        groupService: fakeGroup, feed: FakeFeedService(), posts: fakePosts)
        await vm.load()
        await vm.toggleLike(itemID: post.id)
        #expect(vm.items.first?.isLiked == true)
        #expect(vm.items.first?.likeCount == 1)
        #expect(fakePosts.likeCalls.first?.liked == true)
    }

    @Test func inviteRecordsUsernameAndReportsSuccess() async {
        let fakeGroup = FakeGroupService()
        let vm = GroupTimelineViewModel(groupID: groupID, myID: myID,
                                        groupService: fakeGroup, feed: FakeFeedService(), posts: FakePostService())
        await vm.invite(username: "@Bob")
        #expect(fakeGroup.invitedCalls.first?.username == "Bob")   // trimmed, @ stripped
        #expect(vm.inviteStatus != nil)
        #expect(vm.inviteError == nil)
    }

    @Test func inviteSurfacesError() async {
        let fakeGroup = FakeGroupService()
        fakeGroup.inviteError = PostErrorStub.boom
        let vm = GroupTimelineViewModel(groupID: groupID, myID: myID,
                                        groupService: fakeGroup, feed: FakeFeedService(), posts: FakePostService())
        await vm.invite(username: "bob")
        #expect(vm.inviteError != nil)
    }
}
