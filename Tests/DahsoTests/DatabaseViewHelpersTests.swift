import XCTest
@testable import Dahso
import DahsoCore

final class DatabaseViewHelpersTests: XCTestCase {
    func testCheckboxFiltersUseExplicitCheckedOperators() {
        let checkedFilter = FilterConfig(property: "done", op: "is_checked", value: "")
        let uncheckedFilter = FilterConfig(property: "done", op: "is_not_checked", value: "")

        XCTAssertTrue(matchesFilter(.checkbox(true), filter: checkedFilter))
        XCTAssertFalse(matchesFilter(.checkbox(false), filter: checkedFilter))
        XCTAssertTrue(matchesFilter(.checkbox(false), filter: uncheckedFilter))
    }

    func testNumberFiltersCompareNumerically() {
        let greaterThan = FilterConfig(property: "score", op: "greater_than", value: "2")
        let lessThanOrEqual = FilterConfig(property: "score", op: "less_than_or_equal", value: "10")

        XCTAssertTrue(matchesFilter(.number(10), filter: greaterThan))
        XCTAssertTrue(matchesFilter(.number(10), filter: lessThanOrEqual))
        XCTAssertFalse(matchesFilter(.number(1), filter: greaterThan))
        XCTAssertEqual(compareValues(.number(10), .number(2)), .orderedDescending)
    }

    func testDateFiltersCompareUsingSortableValues() {
        let marchFirst = DatabaseDateValue(start: "2026-03-01").rawValue
        let marchTenth = DatabaseDateValue(start: "2026-03-10").rawValue
        let beforeFilter = FilterConfig(property: "date", op: "less_than", value: marchTenth)

        XCTAssertTrue(matchesFilter(.date(marchFirst), filter: beforeFilter))
        XCTAssertFalse(matchesFilter(.date(marchTenth), filter: beforeFilter))
        XCTAssertEqual(compareValues(.date(marchFirst), .date(marchTenth)), .orderedAscending)
    }
}
