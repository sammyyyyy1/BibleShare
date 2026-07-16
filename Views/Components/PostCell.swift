import SwiftUI

struct PostCell: View {
    let item: FeedItem
    let isMine: Bool
    let onLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let title = item.title {
                Text(title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
            }
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(item.verses) { VerseCard(verse: $0) }

            if !item.media.isEmpty { MediaStrip(media: item.media) }

            if !item.tags.isEmpty {
                Text("with " + item.tags.compactMap { $0.profile?.username }.map { "@\($0)" }
                        .joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            actions
        }
        .padding(16)
        .background(Theme.field)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.indigo).frame(width: 28, height: 28)
                .overlay(
                    Text(String(item.author?.username.prefix(1) ?? "?").uppercased())
                        .font(.caption2).foregroundStyle(.white)
                )
            Text("@\(item.author?.username ?? "unknown")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(Theme.muted)
            Spacer()
            if isMine {
                Menu {
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)     // tap target
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button(action: onLike) {
                HStack(spacing: 5) {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(item.isLiked ? Theme.danger : Theme.muted)
                    Text("\(item.likeCount)").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isLiked ? "Unlike" : "Like")

            Button(action: onComment) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right").foregroundStyle(Theme.muted)
                    Text("\(item.commentCount)").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            Spacer()
        }
        .padding(.top, 2)
    }
}
