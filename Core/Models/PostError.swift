import Foundation

/// Shared error type for social write/read paths. Consumed by nearly every
/// ViewModel, so it is shared kernel rather than owned by one feature.
enum PostError {
    /// Maps a thrown error to user-facing copy, separating the recoverable
    /// (retry) from the terminal (surface and stop).
    static func message(for error: Error) -> String {
        if error is BibleError { return "Couldn't load that passage. Check the reference and try again." }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "You appear to be offline. Try again." }
        let text = "\(error)"
        if text.contains("title is required") { return "An encouragement needs a title." }
        if text.contains("own storage folder") { return "That image couldn't be attached. Try picking it again." }
        if text.contains("username not found") { return "We couldn't find that username." }
        if text.contains("cannot send a friend request to yourself") { return "You can't add yourself." }
        if text.contains("already friends") { return "You're already friends." }
        if text.contains("no pending friend request") { return "That request is no longer available." }
        if text.contains("already in this group") { return "You're already in this group." }
        if text.contains("already a member") { return "They're already a member." }
        if text.contains("only the group creator can invite") { return "Only the group's creator can invite people." }
        if text.contains("you can only post to groups you belong to") { return "You can only post to groups you belong to." }
        if text.contains("at least one destination") { return "Choose your timeline or at least one group." }
        if text.contains("group name must be") { return "A group name must be 1–60 characters." }
        if text.contains("no pending invite") { return "That invite is no longer available." }
        if text.contains("no active check-in window") { return "That check-in window has closed." }
        if text.contains("already checked in") { return "You've already checked in there." }
        if text.contains("a check-in needs at least one group") { return "Choose at least one group." }
        if text.contains("weekday must be between 0 and 6") { return "Pick a day of the week." }
        if text.contains("a check-in schedule needs a time") { return "Pick a time for the check-in." }
        if text.contains("a weekly schedule needs a weekday") { return "Pick a weekday for the check-in." }
        if text.contains("unknown timezone") { return "That time zone isn't recognized." }
        if text.contains("you can only tag people who can see this post") {
            return "You can only tag people who can see this post."
        }
        if text.contains("42501") || text.lowercased().contains("row-level security") {
            return "You don't have permission to do that."
        }
        return "Something went wrong. Please try again."
    }
}
