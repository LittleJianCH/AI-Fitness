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

    func testCalendarBoundsAndExplicitCompleteness() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        XCTAssertTrue(TrainingCalendar.days(ending: Date(), count: 0, timeZone: zone, complete: true).isEmpty)
        XCTAssertTrue(TrainingCalendar.days(ending: Date(), count: 367, timeZone: zone, complete: true).isEmpty)
        let days = TrainingCalendar.days(ending: Date(), count: 2, timeZone: zone, complete: true)
        XCTAssertEqual(days.count, 2)
        XCTAssertTrue(days.allSatisfy(\.calendarRecordingComplete))
    }
}
