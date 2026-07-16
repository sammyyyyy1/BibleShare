import Foundation

/// An image picked but not yet uploaded. Held as encoded JPEG bytes so the
/// ViewModel stays free of UIKit and is testable.
struct ComposeImage: Identifiable, Hashable, Sendable {
    let id: UUID
    let jpeg: Data
}

@MainActor
@Observable
final class ComposeViewModel {
    static let maxImages = 4

    var title = ""
    var body = ""
    var sharedToTimeline = true
    var verses: [NewVerse] = []
    var links: [NewMediaItem] = []
    var pendingImages: [ComposeImage] = []
    var taggedUsers: [Profile] = []
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let posts: PostServicing
    private let uploader: MediaUploading
    private let resolver: UsernameResolving
    private let bible: BibleFetching

    init(posts: PostServicing = PostService.shared,
         uploader: MediaUploading = MediaUploader.shared,
         resolver: UsernameResolving = ProfileService.shared,
         bible: BibleFetching = BibleService.shared) {
        self.posts = posts
        self.uploader = uploader
        self.resolver = resolver
        self.bible = bible
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool { !trimmedTitle.isEmpty && !isSubmitting }
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

            let params = CreateEncouragementParams(
                title: trimmedTitle,
                body: {
                    let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }(),
                sharedToTimeline: sharedToTimeline,
                verses: verses,
                media: media,
                tagUserIDs: taggedUsers.map(\.id)
            )
            return try await posts.createEncouragement(params)
        } catch {
            // Compensating delete: without this, every failed submit strands objects.
            try? await uploader.delete(paths: uploadedPaths)
            errorMessage = PostError.message(for: error)
            return nil
        }
    }
}
