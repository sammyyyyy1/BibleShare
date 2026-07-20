import Foundation

@MainActor
@Observable
final class FriendsViewModel {
    private(set) var edges: [FriendEdge] = []
    private(set) var isLoading = false
    private(set) var isAdding = false
    /// Sheet-level failures (load/respond).
    var errorMessage: String?
    /// Success note under the add-friend field ("Request sent." / "You're now friends.").
    var addStatus: String?
    /// Failure note under the add-friend field.
    var addError: String?
    /// Client-side filter text for the friends list (no server call).
    var searchText = ""

    let myID: UUID
    private let service: FriendServicing

    init(myID: UUID, service: FriendServicing = FriendService.shared) {
        self.myID = myID
        self.service = service
    }

    /// Pending requests others sent me.
    var incoming: [FriendEdge] { edges.filter { $0.status == .pending && $0.addresseeID == myID } }
    /// Pending requests I sent.
    var outgoing: [FriendEdge] { edges.filter { $0.status == .pending && $0.requesterID == myID } }
    /// Accepted friendships (either direction).
    var accepted: [FriendEdge] { edges.filter { $0.status == .accepted } }

    /// Case-insensitive substring match across username and display name,
    /// like mainstream social apps — but strictly over the already-accepted
    /// friends list (adding stays exact-username-only).
    var filteredFriends: [FriendEdge] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return accepted }
        return accepted.filter { edge in
            guard let person = edge.otherParty(myID: myID) else { return false }
            return person.username.lowercased().contains(query)
                || (person.displayName?.lowercased().contains(query) ?? false)
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            edges = try await service.fetchEdges(userID: myID)
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func addFriend(username: String) async {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty, !isAdding else { return }
        isAdding = true
        addStatus = nil
        addError = nil
        defer { isAdding = false }
        do {
            let friendship = try await service.sendRequest(username: cleaned)
            addStatus = friendship.status == .accepted ? "You're now friends." : "Request sent."
            await load()
        } catch {
            addError = PostError.message(for: error)
        }
    }

    func respond(requesterID: UUID, accept: Bool) async {
        do {
            try await service.respond(requesterID: requesterID, accept: accept)
            await load()
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }
}
