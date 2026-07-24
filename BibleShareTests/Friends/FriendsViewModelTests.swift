import Testing
import Foundation
@testable import BibleShare

/// Mirrors an RPC error body so PostError.message(for:) string-matches.
private struct FakeRPCError: Error {
    let message: String
}

@MainActor
struct FriendsViewModelTests {
    private let me = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    private let other = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "cccccccc-0000-0000-0000-000000000003")!

    private func profile(_ id: UUID, _ username: String, _ displayName: String? = nil) -> Profile {
        Profile(id: id, username: username, usernameSet: true, displayName: displayName,
                avatarURL: nil, bio: nil, createdAt: Date())
    }

    private func edge(requester: UUID, addressee: UUID, status: FriendStatus,
                      requesterProfile: Profile? = nil, addresseeProfile: Profile? = nil) -> FriendEdge {
        FriendEdge(requesterID: requester, addresseeID: addressee, status: status,
                   createdAt: Date(), respondedAt: status == .accepted ? Date() : nil,
                   requester: requesterProfile, addressee: addresseeProfile)
    }

    // MARK: classification

    @Test func classifiesIncomingOutgoingAccepted() async {
        let fake = FakeFriendService()
        fake.edges = [
            edge(requester: other, addressee: me, status: .pending),     // incoming
            edge(requester: me, addressee: third, status: .pending),     // outgoing
            edge(requester: other, addressee: me, status: .accepted),    // accepted
            edge(requester: me, addressee: third, status: .accepted),    // accepted
        ]
        let vm = FriendsViewModel(myID: me, service: fake)
        await vm.load()
        #expect(vm.incoming.count == 1)
        #expect(vm.outgoing.count == 1)
        #expect(vm.accepted.count == 2)
        #expect(vm.incoming.first?.requesterID == other)
        #expect(vm.outgoing.first?.addresseeID == third)
    }

    // MARK: friends-list filter

    @Test func filterMatchesUsernameAndDisplayNameCaseInsensitively() async {
        let fake = FakeFriendService()
        fake.edges = [
            edge(requester: other, addressee: me, status: .accepted,
                 requesterProfile: profile(other, "bob", "Bob B")),
            edge(requester: third, addressee: me, status: .accepted,
                 requesterProfile: profile(third, "carol", "Carol C")),
        ]
        let vm = FriendsViewModel(myID: me, service: fake)
        await vm.load()

        vm.searchText = "BOB"
        #expect(vm.filteredFriends.count == 1)
        #expect(vm.filteredFriends.first?.requesterID == other)

        vm.searchText = "carol c"          // display-name match
        #expect(vm.filteredFriends.count == 1)
        #expect(vm.filteredFriends.first?.requesterID == third)

        vm.searchText = "zzz"
        #expect(vm.filteredFriends.isEmpty)

        vm.searchText = "   "              // blank = no filter
        #expect(vm.filteredFriends.count == 2)
    }

    // MARK: add friend

    @Test func addFriendPendingShowsRequestSentAndReloads() async {
        let fake = FakeFriendService()
        fake.sendResults = [Friendship(requesterID: me, addresseeID: other,
                                       status: .pending, createdAt: Date(), respondedAt: nil)]
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.addFriend(username: "  @Bob  ")

        #expect(vm.addStatus == "Request sent.")
        #expect(vm.addError == nil)
        #expect(fake.sentUsernames == ["Bob"])   // whitespace + @ stripped, case preserved
        #expect(fake.fetchCount == 1)            // list refreshed after the write
    }

    @Test func addFriendAutoAcceptShowsNowFriends() async {
        let fake = FakeFriendService()
        fake.sendResults = [Friendship(requesterID: other, addresseeID: me,
                                       status: .accepted, createdAt: Date(), respondedAt: Date())]
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.addFriend(username: "bob")

        #expect(vm.addStatus == "You're now friends.")
        #expect(vm.addError == nil)
    }

    @Test func addFriendMapsRPCErrorsToCopy() async {
        let fake = FakeFriendService()
        let vm = FriendsViewModel(myID: me, service: fake)

        fake.sendError = FakeRPCError(message: "username not found")
        await vm.addFriend(username: "ghost")
        #expect(vm.addError == "We couldn't find that username.")
        #expect(vm.addStatus == nil)

        // A later success clears the error.
        fake.sendError = nil
        await vm.addFriend(username: "bob")
        #expect(vm.addError == nil)
        #expect(vm.addStatus == "Request sent.")

        fake.sendError = FakeRPCError(message: "already friends")
        await vm.addFriend(username: "bob")
        #expect(vm.addError == "You're already friends.")

        fake.sendError = FakeRPCError(message: "cannot send a friend request to yourself")
        await vm.addFriend(username: "me")
        #expect(vm.addError == "You can't add yourself.")
    }

    @Test func addFriendIgnoresBlankInput() async {
        let fake = FakeFriendService()
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.addFriend(username: "   ")
        #expect(fake.sentUsernames.isEmpty)
        #expect(vm.addStatus == nil && vm.addError == nil)
    }

    // MARK: respond

    @Test func respondAcceptAndDeclineCallServiceAndReload() async {
        let fake = FakeFriendService()
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.respond(requesterID: other, accept: true)
        await vm.respond(requesterID: third, accept: false)

        #expect(fake.respondCalls.count == 2)
        #expect(fake.respondCalls[0].requesterID == other)
        #expect(fake.respondCalls[0].accept == true)
        #expect(fake.respondCalls[1].requesterID == third)
        #expect(fake.respondCalls[1].accept == false)
        #expect(fake.fetchCount == 2)             // one reload per response
        #expect(vm.errorMessage == nil)
    }

    @Test func respondFailureSurfacesError() async {
        let fake = FakeFriendService()
        fake.respondError = FakeRPCError(message: "no pending friend request from that user")
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.respond(requesterID: other, accept: true)

        #expect(vm.errorMessage == "That request is no longer available.")
        #expect(fake.fetchCount == 0)             // no reload after a failed write
    }

    // MARK: load

    @Test func loadPopulatesEdgesAndSections() async {
        let fake = FakeFriendService()
        fake.edges = [
            edge(requester: other, addressee: me, status: .pending),
            edge(requester: me, addressee: third, status: .accepted),
        ]
        let vm = FriendsViewModel(myID: me, service: fake)

        await vm.load()

        #expect(vm.edges.count == 2)
        #expect(vm.incoming.count == 1)
        #expect(vm.accepted.count == 1)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadFailureSurfacesError() async {
        struct Boom: Error {}
        final class FailingFriendService: FriendServicing, @unchecked Sendable {
            func sendRequest(username: String) async throws -> Friendship { throw Boom() }
            func respond(requesterID: UUID, accept: Bool) async throws { throw Boom() }
            func fetchEdges(userID: UUID) async throws -> [FriendEdge] { throw Boom() }
        }
        let vm = FriendsViewModel(myID: me, service: FailingFriendService())

        await vm.load()

        #expect(vm.edges.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }
}
