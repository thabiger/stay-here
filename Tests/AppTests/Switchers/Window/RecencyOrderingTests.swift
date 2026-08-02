import XCTest
@testable import StayHereApp

final class RecencyOrderingTests: XCTestCase {
    func testCompleteMergeKeepsRecencyOrderAndAppendsUnknown() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [3, 2, 1], incomingIDs: [4, 3], promoting: [], scope: .complete),
            [3, 4]
        )
    }

    func testCompleteMergePrunesStaleIDs() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [103, 201, 102, 101], incomingIDs: [302, 301], promoting: [], scope: .complete),
            [302, 301]
        )
    }

    func testSubsetMergePreservesUnlistedIDsInPriorOrder() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [103, 201, 102, 101], incomingIDs: [201], promoting: [], scope: .subset),
            [201, 103, 102, 101]
        )
    }

    func testSubsetMergeAppendsUnknownAfterKnown() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [2], incomingIDs: [1, 2, 3], promoting: [], scope: .subset),
            [2, 1, 3]
        )
    }

    func testEmptyIncomingSubsetPreservesList() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [1, 2], incomingIDs: [], promoting: [], scope: .subset),
            [1, 2]
        )
    }

    func testEmptyIncomingCompleteWipes() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [1, 2], incomingIDs: [], promoting: [], scope: .complete),
            []
        )
    }

    func testPromotingForcesPrefixInCommitOrder() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [103, 201, 102, 101], incomingIDs: [302, 301], promoting: [302, 301], scope: .subset),
            [302, 301, 103, 201, 102, 101]
        )
    }

    func testPromotingDeduplicatesAgainstKnown() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [3, 1, 2], incomingIDs: [1, 2, 3], promoting: [3], scope: .complete),
            [3, 1, 2]
        )
    }

    func testPromotingIsDeduplicated() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [1, 2], incomingIDs: [1, 2], promoting: [2, 2], scope: .complete),
            [2, 1]
        )
    }

    func testCompleteCommitStyleReplace() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [101, 102, 201, 103], incomingIDs: [302, 301], promoting: [302, 301], scope: .complete),
            [302, 301]
        )
    }

    func testPromotedIDsExcludedFromSubsetTail() {
        XCTAssertEqual(
            RecencyOrdering.merge(recentIDs: [1, 2, 3], incomingIDs: [1, 2], promoting: [1], scope: .subset),
            [1, 2, 3]
        )
    }
}
