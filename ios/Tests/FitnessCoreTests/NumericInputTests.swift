import Foundation
import XCTest
@testable import FitnessCore

final class NumericInputTests: XCTestCase {
    func testRejectsIncompleteAndNonfiniteNumbers() {
        for identifier in ["en_US", "en_GB", "zh_Hans_CN", "de_DE"] {
            let locale = Locale(identifier: identifier)
            for input in ["", " ", "72abc", "72.5.4", "72,5,4", "NaN", "∞", "1e999"] {
                XCTAssertNil(NumericInput.parse(input, locale: locale), "\(identifier): \(input)")
            }
        }
    }

    func testPreservesLocaleDecimalsGroupingAndSign() {
        for identifier in ["en_US", "en_GB", "zh_Hans_CN"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(NumericInput.parse(" 72.5\n", locale: locale), 72.5)
            XCTAssertEqual(NumericInput.parse("1,234.5", locale: locale), 1234.5)
            XCTAssertNil(NumericInput.parse("72,5", locale: locale))
            XCTAssertEqual(NumericInput.parse("0", locale: locale), 0)
            XCTAssertEqual(NumericInput.parse("-1", locale: locale), -1)
        }
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(NumericInput.parse("72,5", locale: german), 72.5)
        XCTAssertEqual(NumericInput.parse("1.234,5", locale: german), 1234.5)
        XCTAssertNil(NumericInput.parse("72.5", locale: german))
    }
}
