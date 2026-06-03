import XCTest
import Core

final class SpaceCyclingTests: XCTestCase {
    func testNextSpaceWrapsAround() {
        XCTAssertEqual(SpaceCycling.nextSpaceID(currentSpaceID: 2, orderedSpaceIDs: [1, 2, 3]), 3)
        XCTAssertEqual(SpaceCycling.nextSpaceID(currentSpaceID: 3, orderedSpaceIDs: [1, 2, 3]), 1)
    }

    func testPreviousSpaceWrapsAround() {
        XCTAssertEqual(SpaceCycling.previousSpaceID(currentSpaceID: 2, orderedSpaceIDs: [1, 2, 3]), 1)
        XCTAssertEqual(SpaceCycling.previousSpaceID(currentSpaceID: 1, orderedSpaceIDs: [1, 2, 3]), 3)
    }

    func testUnknownCurrentSpaceFallsBackToEdge() {
        XCTAssertEqual(SpaceCycling.nextSpaceID(currentSpaceID: nil, orderedSpaceIDs: [10, 20, 30]), 10)
        XCTAssertEqual(SpaceCycling.previousSpaceID(currentSpaceID: nil, orderedSpaceIDs: [10, 20, 30]), 30)
        XCTAssertEqual(SpaceCycling.nextSpaceID(currentSpaceID: 99, orderedSpaceIDs: [10, 20, 30]), 10)
        XCTAssertEqual(SpaceCycling.previousSpaceID(currentSpaceID: 99, orderedSpaceIDs: [10, 20, 30]), 30)
    }
}
