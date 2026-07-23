import Foundation
import os

/// An image picked but not yet uploaded. Held as encoded JPEG bytes so the
/// ViewModel stays free of UIKit and is testable.
struct ComposeImage: Identifiable, Hashable, Sendable {
    let id: UUID
    let jpeg: Data
}

/// Encouragement (title required, timeline-or-groups destination) vs check-in
/// (title optional, groups-with-open-window targets only, never the timeline).
enum ComposeMode: Sendable {
    case encouragement
    case checkIn
}

@MainActor
@Observable
final class ComposeViewModel {
    static let maxImages = 4

    let mode: ComposeMode

    var title = ""
    var body = ""
    var sharedToTimeline = true
    var verses: [NewVerse] = []
    var links: [NewMediaItem] = []
    var pendingImages: [ComposeImage] = []
    var taggedUsers: [Profile] = []
    private(set) var isSubmitting = false
    var errorMessage: String?
    var myGroups: [GroupListItem] = []
    var selectedGroupIDs: Set<UUID> = []

    /// Check-in mode: groups with an open, unanswered window for the caller.
    var checkinTargets: [CheckinTarget] = []

    private let posts: PostServicing
    private let uploader: MediaUploading
    private let resolver: UsernameResolving
    private let bible: BibleFetching
    private let groups: GroupServicing

    init(mode: ComposeMode = .encouragement,
         posts: PostServicing = PostService.shared,
         uploader: MediaUploading = MediaUploader.shared,
         resolver: UsernameResolving = ProfileService.shared,
         bible: BibleFetching = BibleService.shared,
         groups: GroupServicing = GroupService.shared) {
        self.mode = mode
        self.posts = posts
        self.uploader = uploader
        self.resolver = resolver
        self.bible = bible
        self.groups = groups
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An encouragement must reach at least one surface — the timeline or a group.
    var hasDestination: Bool { sharedToTimeline || !selectedGroupIDs.isEmpty }

    var canSubmit: Bool {
        guard !isSubmitting, pendingImages.count <= Self.maxImages else { return false }
        switch mode {
        case .encouragement:
            return !trimmedTitle.isEmpty && hasDestination
        case .checkIn:
            return !selectedGroupIDs.isEmpty
        }
    }
    var canAddImage: Bool { pendingImages.count < Self.maxImages }

    // MARK: Attachments

    func addVerse(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async {
        errorMessage = nil
        do {
            let passage = try await bible.fetch(book: book, chapter: chapter,
                                                verseStart: verseStart, verseEnd: verseEnd)
            verses.append(NewVerse(book: book,
                                   chapter: chapter,
                                   verseStart: verseStart,
                                   verseEnd: max(verseEnd, verseStart),
                                   referenceLabel: passage.referenceLabel,
                                   textSnapshot: passage.text,
                                   position: verses.count))
        } catch {
            // Never attach a verse with an empty snapshot — the post would render blank forever.
            errorMessage = PostError.message(for: error)
        }
    }

    func removeVerse(id: UUID) {
        verses.removeAll { $0.id == id }
        for index in verses.indices { verses[index].position = index }
    }

    func addTag(username: String) async {
        errorMessage = nil
        do {
            guard let profile = try await resolver.resolveExact(username) else {
                errorMessage = "No user named \(username.hasPrefix("@") ? username : "@" + username)."
                return
            }
            guard !taggedUsers.contains(where: { $0.id == profile.id }) else { return }
            taggedUsers.append(profile)
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func addLink(url: String, title: String?) {
        links.append(NewMediaItem(mediaType: .link,
                                  url: url,
                                  thumbnailURL: nil,
                                  title: title,
                                  description: nil,
                                  position: 0))   // real positions assigned at submit
    }

    /// Loads the caller's groups for the compose multi-select. Non-fatal: if it
    /// fails, groups just don't appear — the timeline path still works.
    func loadGroups(userID: UUID) async {
        do { myGroups = try await groups.fetchMyGroups(userID: userID) }
        catch { /* leave myGroups empty; not worth blocking compose */ }
    }

    /// Pre-select a group (the group-timeline "Post here" entry point).
    func preselect(groupID: UUID) {
        selectedGroupIDs.insert(groupID)
    }

    /// Check-in mode: loads groups with an open, unanswered window. Non-fatal,
    /// mirroring loadGroups — the Check-in tab shows its own empty state.
    func loadCheckinTargets() async {
        do { checkinTargets = try await groups.fetchActiveCheckinTargets() }
        catch { /* leave checkinTargets empty */ }
    }

    // MARK: Submit

    /// Uploads images, then writes the post. On failure, sweeps the objects it
    /// just uploaded and keeps the draft intact (spec §5.1).
    func submit(userID: UUID) async -> UUID? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var uploadedPaths: [String] = []
        do {
            for image in pendingImages {
                uploadedPaths.append(try await uploader.upload(image.jpeg, userID: userID))
            }

            var media = uploadedPaths.enumerated().map { index, path in
                NewMediaItem(mediaType: .image, url: path, thumbnailURL: nil,
                             title: nil, description: nil, position: index)
            }
            media += links.enumerated().map { index, link in
                NewMediaItem(mediaType: .link, url: link.url, thumbnailURL: link.thumbnailURL,
                             title: link.title, description: link.description,
                             position: uploadedPaths.count + index)
            }

            switch mode {
            case .encouragement:
                let params = CreateEncouragementParams(
                    title: trimmedTitle,
                    body: {
                        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty ? nil : t
                    }(),
                    sharedToTimeline: sharedToTimeline,
                    groupIDs: Array(selectedGroupIDs),
                    verses: verses,
                    media: media,
                    tagUserIDs: taggedUsers.map(\.id)
                )
                return try await posts.createEncouragement(params)
            case .checkIn:
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let params = CheckInParams(
                    groupIDs: Array(selectedGroupIDs),
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    body: trimmedBody.isEmpty ? nil : trimmedBody,
                    verses: verses,
                    media: media,
                    tagUserIDs: taggedUsers.map(\.id)
                )
                return try await posts.checkIn(params)
            }
        } catch {
            // Compensating delete: without this, every failed submit strands objects.
            // If the sweep itself also fails, log it (there is no cleanup job
            // anywhere in this system, so a silent failure here orphans the
            // objects permanently) but surface the ORIGINAL error to the user —
            // they care that their post failed to send, not that cleanup did too.
            do {
                try await uploader.delete(paths: uploadedPaths)
            } catch let sweepError {
                Logger(subsystem: "com.bibleshare.app", category: "compose")
                    .error("Failed to sweep orphaned upload(s) \(uploadedPaths) after a failed submit: \(sweepError)")
            }
            errorMessage = PostError.message(for: error)
            return nil
        }
    }
}
