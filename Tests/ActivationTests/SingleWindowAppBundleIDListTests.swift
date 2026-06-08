import XCTest
import Core

final class SingleWindowAppBundleIDListTests: XCTestCase {
    func testParseExtractsTrimmedNonEmptyBundleIDs() {
        let result = SingleWindowAppBundleIDList.parse(
            """
            com.apple.Notes
              com.openai.codex

            \tcom.example.App
            """
        )
        XCTAssertEqual(result, ["com.apple.Notes", "com.openai.codex", "com.example.App"])
    }

    func testParseDeduplicatesIdenticalBundleIDs() {
        let result = SingleWindowAppBundleIDList.parse(
            """
            com.apple.Notes
            com.apple.Notes
            com.openai.codex
            """
        )
        XCTAssertEqual(result, ["com.apple.Notes", "com.openai.codex"])
    }

    func testParseDropsBlankLines() {
        let result = SingleWindowAppBundleIDList.parse("\n\n   \n")
        XCTAssertEqual(result, [])
    }

    func testSerializeJoinsBundleIDsWithNewlines() {
        let result = SingleWindowAppBundleIDList.serialize(["com.apple.Notes", "com.openai.codex"])
        XCTAssertEqual(result, "com.apple.Notes\ncom.openai.codex")
    }

    func testSerializeTrimsAndDeduplicates() {
        let result = SingleWindowAppBundleIDList.serialize([
            "  com.apple.Notes  ",
            "",
            "com.apple.Notes",
            "com.openai.codex"
        ])
        XCTAssertEqual(result, "com.apple.Notes\ncom.openai.codex")
    }

    func testParseAndSerializeRoundTrip() {
        let bundleIDs = ["com.example.A", "com.example.B", "com.example.C"]
        let serialized = SingleWindowAppBundleIDList.serialize(bundleIDs)
        XCTAssertEqual(SingleWindowAppBundleIDList.parse(serialized), bundleIDs)
    }
}
