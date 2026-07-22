import Testing
import Foundation
@testable import BibleShare

struct CheckinReminderSchedulerTests {
    private func group(cadence: CheckinCadence, time: String?, weekday: Int?, tz: String) -> FellowshipGroup {
        FellowshipGroup(id: UUID(), creatorID: UUID(), name: "G", description: nil,
                        checkinCadence: cadence, checkinTime: time, checkinWeekday: weekday,
                        timezone: tz, createdAt: Date())
    }

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    @Test func dailyProducesConsecutiveDaysAtTheGroupsLocalTime() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T18:00:00Z"), count: 3)

        #expect(dates.count == 3)
        // 08:00 New York on 22 Jul = 12:00Z (EDT, UTC-4)
        #expect(dates[0] == iso("2026-07-22T12:00:00Z"))
        #expect(dates[1] == iso("2026-07-23T12:00:00Z"))
    }

    @Test func dailyLaterTodayStillCountsAsTheNextOccurrence() {
        let g = group(cadence: .daily, time: "20:00:00", weekday: nil, tz: "UTC")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 1)
        #expect(dates[0] == iso("2026-07-21T20:00:00Z"))
    }

    @Test func weeklyLandsOnTheRequestedWeekday() {
        // weekday 0 = Sunday, matching the Postgres convention used by due_slot_for.
        let g = group(cadence: .weekly, time: "09:00:00", weekday: 0, tz: "UTC")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 2)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.component(.weekday, from: dates[0]) == 1)  // Foundation: 1 = Sunday
        #expect(dates[1].timeIntervalSince(dates[0]) == 7 * 86_400)
    }

    /// The group's own timezone governs, not the device's — a traveller must
    /// not get reminders shifted by wherever they happen to be.
    @Test func springForwardKeepsTheGroupsWallClockTime() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-03-07T18:00:00Z"), count: 3)
        // 8 Mar 2026 is the US spring-forward. 08:00 local is 13:00Z before and
        // 12:00Z after, and the wall-clock time must stay 08:00 either way.
        #expect(dates[0] == iso("2026-03-08T12:00:00Z"))
    }

    @Test func cadenceNoneProducesNothing() {
        let g = group(cadence: .none, time: nil, weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func aMissingTimeProducesNothingRatherThanGuessing() {
        let g = group(cadence: .daily, time: nil, weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func anUnknownTimezoneProducesNothingRatherThanFallingBackToDeviceLocal() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "Mars/Olympus")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }
}
