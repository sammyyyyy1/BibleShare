import SwiftUI

struct MediaStrip: View {
    let media: [PostMedia]

    private var images: [PostMedia] { media.filter { $0.mediaType == .image } }
    private var links: [PostMedia] { media.filter { $0.mediaType == .link } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images) { item in
                            RemoteImage(path: item.url)
                                .frame(width: 200, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                        }
                    }
                }
            }
            ForEach(links) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "link").foregroundStyle(Theme.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title ?? link.url)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(url.host() ?? link.url)
                                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }
                }
            }
        }
    }
}
