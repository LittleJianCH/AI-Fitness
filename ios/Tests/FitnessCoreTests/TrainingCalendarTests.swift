import Foundation
import XCTest
@testable import FitnessCore

final class TrainingCalendarTests: XCTestCase {
    func testCalendarUsesDayBoundariesAcrossDaylightSavingInsteadOf86400SecondOffsets() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-09T16:00:00Z"))
        let days = TrainingCalendar.days(ending: date, count: 3, timeZone: zone, complete: false)
        XCTAssertEqual(days.map(\.calendarDate), ["2026-03-07", "2026-03-08", "2026-03-09"])
        XCTAssertEqual(days[1].calendarEnd.timeIntervalSince(days[1].calendarStart), 23 * 3600)
        XCTAssertEqual(days[0].calendarEnd, days[1].calendarStart)
        XCTAssertEqual(days[1].calendarEnd, days[2].calendarStart)
        XCTAssertFalse(days[0].calendarRecordingComplete)
    }

    func testCalendarCrossesMidnightDaylightSavingWithoutOverlappingDays() throws {
        try assertSantiagoDays(ending: "2026-09-07T16:00:00Z", dates: ["2026-09-05", "2026-09-06", "2026-09-07"],
                               boundaries: ["2026-09-05T04:00:00Z", "2026-09-06T04:00:00Z", "2026-09-07T03:00:00Z", "2026-09-08T03:00:00Z"])
    }

    func testCalendarEndingOnMidnightDaylightSavingDoesNotShiftEarlierDays() throws {
        try assertSantiagoDays(ending: "2026-09-06T16:00:00Z", dates: ["2026-09-04", "2026-09-05", "2026-09-06"],
                               boundaries: ["2026-09-04T04:00:00Z", "2026-09-05T04:00:00Z", "2026-09-06T04:00:00Z", "2026-09-07T03:00:00Z"])
    }

    private func assertSantiagoDays(ending: String, dates: [String], boundaries: [String]) throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: ending))
        let expected = try boundaries.map { try XCTUnwrap(formatter.date(from: $0)) }
        let days = TrainingCalendar.days(ending: date, count: dates.count, timeZone: zone, complete: true)
        XCTAssertEqual(days.map(\.calendarDate), dates)
        XCTAssertEqual(days.map(\.calendarStart), Array(expected.dropLast()))
        XCTAssertEqual(days.map(\.calendarEnd), Array(expected.dropFirst()))
        for (day, next) in zip(days, days.dropFirst()) { XCTAssertEqual(day.calendarEnd, next.calendarStart) }
        let transition = try XCTUnwrap(days.first { $0.calendarDate == "2026-09-06" })
        XCTAssertEqual(transition.calendarEnd.timeIntervalSince(transition.calendarStart), 23 * 3600)
    }

    func testCalendarBoundsAndExplicitCompleteness() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        XCTAssertTrue(TrainingCalendar.days(ending: Date(), count: 0, timeZone: zone, complete: true).isEmpty)
        XCTAssertTrue(TrainingCalendar.days(ending: Date(), count: 367, timeZone: zone, complete: true).isEmpty)
        let days = TrainingCalendar.days(ending: Date(), count: 2, timeZone: zone, complete: true)
        XCTAssertEqual(days.count, 2)
        XCTAssertTrue(days.allSatisfy(\.calendarRecordingComplete))
    }
}
