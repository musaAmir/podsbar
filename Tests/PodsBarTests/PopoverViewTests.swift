import XCTest
@testable import PodsBar

@MainActor
final class PopoverViewTests: XCTestCase {
    func testTileFillMatchesTheMenuBarGlyph() {
        XCTAssertNil(BatteryTile.fillFraction(for: nil))
        // A case can report 0%; the glyph leaves that capsule empty and so should the tile.
        XCTAssertNil(BatteryTile.fillFraction(for: 0))
        XCTAssertEqual(BatteryTile.fillFraction(for: 1), 0.08)
        XCTAssertEqual(BatteryTile.fillFraction(for: 56), 0.56)
        XCTAssertEqual(BatteryTile.fillFraction(for: 100), 1)
    }
}
