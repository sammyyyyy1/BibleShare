import SwiftUI

/// Loads a private `media` object by asking for a short-lived signed URL.
/// The bucket is private, so AsyncImage cannot hit the path directly.
struct RemoteImage: View {
    let path: String
    var uploader: MediaUploading = MediaUploader.shared

    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                placeholder.overlay(
                    Image(systemName: "photo").foregroundStyle(Theme.muted)
                )
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    default: placeholder.overlay(ProgressView().tint(Theme.muted))
                    }
                }
            } else {
                placeholder.overlay(ProgressView().tint(Theme.muted))
            }
        }
        .task(id: path) {
            failed = false
            url = nil
            do { url = try await uploader.signedURL(path: path) }
            catch { failed = true }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Theme.hairline.opacity(0.5))
    }
}
