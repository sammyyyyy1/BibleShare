import Foundation
import UserNotifications

/// Local check-in reminders. APNs has no signing key yet (spec §7.3), so the
/// reminder that would arrive as a push is scheduled on-device instead.
enum CheckinReminderScheduler {
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    static let maxPending = 48
    private static let prefix = "checkin-"

    /// Strictly parses "HH:MM" or "HH:MM:SS". Every colon-separated segment
    /// must be entirely numeric - `compactMap { Int($0) }` would silently drop
    /// a non-numeric segment (e.g. ["aa","00","00"] -> [0,0]), fabricating a
    /// midnight reminder instead of failing. Here the parsed count must match
    /// the segment count, there must be 2 or 3 segments, and each value must
    /// be in range; anything else returns `nil`.
    private static func parseTimeOfDay(_ hhmmss: String) -> (hour: Int, minute: Int, second: Int)? {
        let segments = hhmmss.split(separator: ":", omittingEmptySubsequences: false)
        guard segments.count == 2 || segments.count == 3 else { return nil }

        let parsed = segments.map { Int($0) }
        guard parsed.allSatisfy({ $0 != nil }) else { return nil }
        let values = parsed.compactMap { $0 }

        let hour = values[0]
        let minute = values[1]
        let second = values.count > 2 ? values[2] : 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }

        return (hour, minute, second)
    }

    /// The next `count` reminder instants for a group, in the GROUP's timezone.
    /// Pure and total: an unusable schedule yields `[]` rather than a guess.
    static func nextOccurrences(for group: FellowshipGroup,
                                after now: Date,
                                count: Int) -> [Date] {
        guard group.checkinCadence != .none,
              let hhmmss = group.checkinTime,
              let zone = TimeZone(identifier: group.timezone),
              let time = parseTimeOfDay(hhmmss)
        else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second

        if group.checkinCadence == .weekly {
            guard let weekday = group.checkinWeekday, (0...6).contains(weekday) else { return [] }
            // Postgres uses 0 = Sunday; Foundation uses 1 = Sunday.
            components.weekday = weekday + 1
        }

        var results: [Date] = []
        var cursor = now
        for _ in 0..<count {
            // matchingPolicy .nextTime resolves a wall-clock time that a DST
            // spring-forward skipped, instead of returning nil.
            //
            // repeatedTimePolicy is set explicitly (not left to Foundation's
            // undocumented default) for the autumn fold, when a wall-clock
            // time occurs twice. `.first` picks the earlier of the two
            // instants - the reminder fires at the first real occurrence of
            // that wall-clock time rather than being delayed by an hour.
            guard let next = calendar.nextDate(after: cursor,
                                               matching: components,
                                               matchingPolicy: .nextTime,
                                               repeatedTimePolicy: .first) else { break }
            results.append(next)
            cursor = next
        }
        return results
    }

    /// Idempotent: replaces this app's check-in requests wholesale, so groups
    /// whose schedule changed (or that were left) cannot leave a stale reminder.
    static func sync(groups: [FellowshipGroup],
                     center: UNUserNotificationCenter = .current(),
                     now: Date = Date()) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix(prefix) })

        // Soonest-first across all groups, so the 64-request ceiling truncates
        // the far future rather than dropping a whole group.
        let upcoming = groups
            .flatMap { group in
                nextOccurrences(for: group, after: now, count: 8).map { (group, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxPending)

        for (group, date) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Time to check in"
            content.body = "\(group.name) is waiting on you"
            content.sound = .default
            content.userInfo = ["type": "checkin_reminder", "group_id": group.id.uuidString]

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: group.timezone) ?? .current
            let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

            let request = UNNotificationRequest(
                identifier: "\(prefix)\(group.id.uuidString)-\(Int(date.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: fields, repeats: false))
            try? await center.add(request)
        }
    }

    /// Asked at the point of value, not at launch.
    @discardableResult
    static func requestAuthorization(
        center: UNUserNotificationCenter = .current()
    ) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
