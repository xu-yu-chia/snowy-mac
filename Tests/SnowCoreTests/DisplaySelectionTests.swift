import XCTest
@testable import SnowCore

/// Which displays get snow: a set of excluded display UUIDs; anything not excluded (including a
/// newly connected display, or one without a UUID) is included.
final class DisplaySelectionTests: XCTestCase {
    func testEveryDisplayIsIncludedByDefault() {
        let selection = DisplaySelection()
        XCTAssertTrue(selection.includes("A"))
        XCTAssertTrue(selection.includes(nil))
    }

    func testTogglingExcludesAndRestores() {
        var selection = DisplaySelection()
        selection.setIncluded(false, for: "A")
        XCTAssertFalse(selection.includes("A"))
        XCTAssertTrue(selection.includes("B"), "Other and new displays stay included")
        selection.setIncluded(true, for: "A")
        XCTAssertTrue(selection.includes("A"))
        XCTAssertEqual(selection.stored, [])
    }

    func testRoundTripsThroughStorage() {
        var selection = DisplaySelection()
        selection.setIncluded(false, for: "B")
        selection.setIncluded(false, for: "A")
        XCTAssertEqual(selection.stored, ["A", "B"])
        XCTAssertEqual(DisplaySelection(stored: selection.stored), selection)
        XCTAssertFalse(DisplaySelection(stored: ["", "A"]).includes(""), "Stored values are taken as given")
    }
}
