import SwiftUI

struct NotificationRow: View {
    let item: NotificationItem

    /// Composed here rather than server-side so a hidden actor degrades to
    /// neutral copy instead of a blank row.
    private var message: String {
        let who = item.actorName
        let group = item.group?.name
        switch item.type {
        case .postLike:         return "\(who) liked your post"
        case .postComment:      return "\(who) commented on your post"
        case .postTag:          return "\(who) tagged you in a post"
        case .memberCheckedIn:  return group.map { "\(who) checked in in \($0)" } ?? "\(who) checked in"
        case .checkinReminder:  return group.map { "\($0) is waiting on you" } ?? "Time to check in"
        case .groupInvite:      return "\(who) invited you to \(group ?? "a group")"
        case .friendRequest:    return "\(who) sent you a friend request"
        case .friendAccepted:   return "\(who) accepted your friend request"
        }
    }

    private var icon: String {
        switch item.type {
        case .postLike:        return "heart.fill"
        case .postComment:     return "bubble.left.fill"
        case .postTag:         return "at"
        case .memberCheckedIn: return "checkmark.circle.fill"
        case .checkinReminder: return "bell.fill"
        case .groupInvite:     return "envelope.fill"
        case .friendRequest,
             .friendAccepted:  return "person.2.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.indigo)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.subheadline)
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isUnread {
                Circle().fill(Theme.indigo).frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
