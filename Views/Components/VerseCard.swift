import SwiftUI

/// A scripture attachment. Renders `text_snapshot`, never a live fetch.
struct VerseCard: View {
    let verse: PostVerse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verse.referenceLabel)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.indigo)
            Text(verse.textSnapshot)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.field)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.indigo).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}
