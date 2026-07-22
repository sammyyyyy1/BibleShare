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

    // MARK: - Finding 1: malformed time must yield [], never a guessed midnight

    @Test func aNonNumericTimeSegmentProducesNothingRatherThanGuessingMidnight() {
        let g = group(cadence: .daily, time: "aa:00:00", weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func anOutOfRangeHourProducesNothing() {
        let g = group(cadence: .daily, time: "25:00:00", weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func anOutOfRangeMinuteProducesNothing() {
        let g = group(cadence: .daily, time: "08:99:00", weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func aGarbageTimeStringProducesNothing() {
        let g = group(cadence: .daily, time: "not-a-time", weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    // MARK: - Finding 2: DST gap and fold must be resolved, not just offset-shifted

    /// 8 Mar 2026 in America/New_York: clocks skip 02:00 -> 03:00, so a 02:30
    /// reminder does not exist that day. The schedule must still fire exactly
    /// once that day, at a real instant after the gap - not be skipped, and
    /// not be duplicated onto the next day.
    @Test func springForwardResolvesAReminderThatFallsInsideTheSkippedGap() {
        let g = group(cadence: .daily, time: "02:30:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-03-07T18:00:00Z"), count: 3)

        #expect(dates.count == 3)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let day0 = cal.dateComponents([.year, .month, .day], from: dates[0])
        #expect(day0.year == 2026 && day0.month == 3 && day0.day == 8)

        // Empirically observed: matchingPolicy .nextTime resolves the skipped
        // 02:30 forward to the first valid instant after the gap, 03:00 local
        // (07:00Z) on 8 Mar 2026 - not a guess, this was run and confirmed.
        #expect(dates[0] == iso("2026-03-08T07:00:00Z"))

        // The following day must not be skipped or duplicated: next occurrence
        // is 9 Mar 02:30 EDT (UTC-4) = 06:30Z, exactly 24h+30m after the gap
        // resolution the day before would be if naively repeated - verify via
        // the actual local wall-clock components instead of a raw offset.
        let day1 = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dates[1])
        #expect(day1.year == 2026 && day1.month == 3 && day1.day == 9)
        #expect(day1.hour == 2 && day1.minute == 30)
    }

    /// 1 Nov 2026 in America/New_York: 01:30 occurs twice (fall-back). The
    /// schedule must yield exactly one occurrence that day, not two.
    @Test func ambiguousAutumnFoldHourYieldsExactlyOneOccurrence() {
        let g = group(cadence: .daily, time: "01:30:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-10-31T18:00:00Z"), count: 3)

        #expect(dates.count == 3)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!

        let novemberFirstOccurrences = dates.filter {
            let c = cal.dateComponents([.year, .month, .day], from: $0)
            return c.year == 2026 && c.month == 11 && c.day == 1
        }
        #expect(novemberFirstOccurrences.count == 1)
    }
}
