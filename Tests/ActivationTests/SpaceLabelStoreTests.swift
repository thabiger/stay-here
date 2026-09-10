import XCTest
@testable import Core
import TestHelpers

@MainActor
final class SpaceLabelStoreTests: XCTestCase {
    func testLoadsPersistedStateFromStore() throws {
        let store = makeStore()
        try store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        XCTAssertEqual(labelStore.labels[101]?.name, "Inbox")
        XCTAssertEqual(labelStore.records[101]?.label.name, "Inbox")
    }

    func testObserveAddsMissingLabelsAndPrunesAbsentSpaceAfterBudget() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        labelStore.observe(
            spaces: [SpaceIdentity(id: 999, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[999]?.name, "Old")
        XCTAssertEqual(labelStore.spaceDisplayByID[999], "display-a")

        // Observing an unknown space creates a default label.
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 999, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop)
            ],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[101]?.name, "Unnamed space")

        // Absence arc: 999 absent from its recorded display-a while display-a stays
        // observed. The wall-clock floor is met (0.5 s per observation → 2.0 s by the
        // fifth), so the label survives observations 1-4 and prunes at observation 5.
        for absence in 1...4 {
            clock.advance(by: 0.5)
            labelStore.observe(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                observedDisplays: ["display-a"]
            )
            XCTAssertEqual(labelStore.labels[999]?.name, "Old",
                           "Absence \(absence): within the budget")
        }

        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertNil(labelStore.labels[999],
                     "Absent for the budget of observations on an observed display → pruned")
        XCTAssertNil(labelStore.spaceDisplayByID[999])
    }

    func testObserveDoesNotDeleteLabelsForEmptyInput() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())
        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.observe(spaces: [], observedDisplays: [])
        XCTAssertEqual(reloaded.labels[999]?.name, "Old", "Empty input must not delete labels")
    }

    func testObserveProtectsLabelsOnUnobservedDisplays() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.observe(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            observedDisplays: ["display-b"]
        )
        XCTAssertEqual(labelStore.spaceDisplayByID[201], "display-b")

        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )

        XCTAssertEqual(labelStore.labels[201]?.name, "Unnamed space",
                       "Labels on an unobserved display must survive a partial snapshot")
        XCTAssertEqual(labelStore.labels[101]?.name, "Unnamed space")
    }

    func testObserveProtectsLabelsWithUnknownDisplay() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        XCTAssertNil(reloaded.spaceDisplayByID[999], "Legacy labels have no display association")

        reloaded.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )

        XCTAssertEqual(reloaded.labels[999]?.name, "Old",
                       "Labels without a recorded display cannot be positively confirmed as removed")
        XCTAssertEqual(reloaded.labels[101]?.name, "Unnamed space")
    }

    func testObserveKeepsLabelOnWithinDisplayPartialSnapshot() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.rename(spaceID: 102, name: "Inbox")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.observe(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(reloaded.labels[102]?.name, "Inbox")
        XCTAssertEqual(reloaded.spaceDisplayByID[102], "display-a")

        // Display-a is observed but 102 is omitted (mid-transition truncation on an
        // otherwise-observed display): one partial observation must not wipe the label.
        reloaded.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(reloaded.labels[102]?.name, "Inbox",
                       "Within-display partial snapshots must not wipe on a single observation")
    }

    func testObservePrunesAbsentSpaceOnlyAfterConsecutiveAbsences() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        labelStore.observe(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space")
        XCTAssertEqual(labelStore.spaceDisplayByID[102], "display-a")

        // Two absences on the observed recorded display: within the budget.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space")
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
            ],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space")

        // Presence before the budget is exhausted resets the absence count.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
            ],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space")

        // Five consecutive absences after the reset, with the floor met, exhaust the
        // budget → pruned.
        for absence in 1...4 {
            clock.advance(by: 0.5)
            labelStore.observe(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 104, display: "display-a", kind: .desktop)
                ],
                observedDisplays: ["display-a"]
            )
            XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space",
                           "Post-reset absence \(absence): within the budget")
        }

        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 104, display: "display-a", kind: .desktop)
            ],
            observedDisplays: ["display-a"]
        )
        XCTAssertNil(labelStore.labels[102])
        XCTAssertNil(labelStore.spaceDisplayByID[102])
    }

    func testObservePresenceOnDifferentDisplayResetsAbsenceCount() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        labelStore.observe(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.spaceDisplayByID[102], "display-a")

        // Two absences on the recorded display-a.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
            ],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space", "Within the budget")

        // Reappears on a DIFFERENT display: the association updates and the absence
        // count resets on any presence regardless of display.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-b", kind: .desktop)
            ],
            observedDisplays: ["display-a", "display-b"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space")
        XCTAssertEqual(labelStore.spaceDisplayByID[102], "display-b")

        // Absent from display-b while display-b is observed: the count restarts from
        // zero. The first observation counts (display-b goes from {102} to {202},
        // shrinking); the second observation is skipped (display-b grows from
        // {202} to {202, 203} triggering the growing-display guard). The single
        // counted absence is still within the budget.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            observedDisplays: ["display-a", "display-b"]
        )
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 203, display: "display-b", kind: .desktop)
            ],
            observedDisplays: ["display-a", "display-b"]
        )
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space",
                       "The reset means the post-reset count (1) is still well within the budget")

        // Four more post-reset absences (5 post-reset counts total, 6 observations
        // overall because the first observation of the expanded display-b set
        // {202,203} is a strict superset of the previous {202} and is skipped by
        // the growing-display guard to avoid false pruning during enumeration lag).
        for _ in 1...4 {
            clock.advance(by: 0.5)
            labelStore.observe(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 202, display: "display-b", kind: .desktop),
                    SpaceIdentity(id: 203, display: "display-b", kind: .desktop)
                ],
                observedDisplays: ["display-a", "display-b"]
            )
        }
        XCTAssertNil(labelStore.labels[102],
                     "Five post-reset absences on the observed recorded display → pruned")
    }

    func testObserveNeverPrunesWithoutWallClockFloor() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        labelStore.observe(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.spaceDisplayByID[102], "display-a")

        // Frozen clock: 8 absence observations exceed the observation budget (5) but
        // the wall-clock floor (2.0 s) is never met → the label must survive.
        for _ in 1...8 {
            labelStore.observe(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                observedDisplays: ["display-a"]
            )
        }
        XCTAssertEqual(labelStore.labels[102]?.name, "Unnamed space",
                       "Count exceeds the budget but the wall-clock floor is unmet → survives")

        // Advancing the clock past the floor completes the budget on the next observation.
        clock.advance(by: 2.0)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertNil(labelStore.labels[102],
                     "Once the floor is met the count completes the budget → pruned")
    }

    func testObserveResetsAbsenceEvidenceWhenRecordedDisplayUnobserved() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        labelStore.observe(
            spaces: [SpaceIdentity(id: 201, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.spaceDisplayByID[201], "display-a")

        // Two counted absences on the observed display-a.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )

        // Display-level gap: only display-b observed → 201's recorded display-a is
        // unobserved, so its pre-gap evidence is reset to zero.
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 301, display: "display-b", kind: .desktop)],
            observedDisplays: ["display-b"]
        )

        // Display-a observed again, 201 still absent: the count restarts at 1 (not 3),
        // so the label survives (it would have completed the budget without the reset).
        clock.advance(by: 0.5)
        labelStore.observe(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            observedDisplays: ["display-a"]
        )
        XCTAssertEqual(labelStore.labels[201]?.name, "Unnamed space",
                       "Gap-reset means the post-gap count restarts from zero")

        // Full post-gap budget with the floor met → pruned.
        for _ in 1...4 {
            clock.advance(by: 0.5)
            labelStore.observe(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                observedDisplays: ["display-a"]
            )
        }
        XCTAssertNil(labelStore.labels[201],
                     "The restarted budget converges on an observed display")
    }

    func testObserveNeverCountsOrPrunesUnknownDisplayLabels() {
        let store = makeStore()
        let clock = TestClock()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger(), now: clock.provider)

        // A label with no recorded display (legacy).
        labelStore.rename(spaceID: 999, name: "Old")
        // A label whose recorded display is the unknown-display sentinel (CGS omitted
        // the `Display Identifier`).
        labelStore.observe(
            spaces: [
                SpaceIdentity(id: 201, display: SpaceLabelStore.unknownDisplayIdentifier, kind: .desktop)
            ],
            observedDisplays: [SpaceLabelStore.unknownDisplayIdentifier]
        )
        XCTAssertEqual(labelStore.spaceDisplayByID[201], SpaceLabelStore.unknownDisplayIdentifier)

        // Exhausted budget with the floor met: neither label can be counted or pruned.
        for _ in 1...8 {
            clock.advance(by: 0.5)
            labelStore.observe(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                observedDisplays: ["display-a"]
            )
        }
        XCTAssertEqual(labelStore.labels[999]?.name, "Old",
                       "Labels without a recorded display are never counted or pruned")
        XCTAssertEqual(labelStore.labels[201]?.name, "Unnamed space",
                       "Labels on the unknown-display sentinel are never counted or pruned")
    }

    func testLoadQuarantinesCorruptStoreFile() {
        let store = makeStore()
        let garbage = Data("not-json-at-all{{{".utf8)
        try? garbage.write(to: store.fileURL)

        let loaded = store.load()
        XCTAssertTrue(loaded.records.isEmpty, "Corrupt file decodes to an empty store")

        let corruptURL = store.fileURL.deletingLastPathComponent()
            .appendingPathComponent(store.fileURL.lastPathComponent + ".corrupt")
        let quarantined = try? Data(contentsOf: corruptURL)
        XCTAssertEqual(quarantined, garbage,
                       "The original corrupt payload must be preserved, not silently overwritten")

        // A subsequent save must not destroy the quarantine file.
        try? store.save(PersistedSpaces(labels: [101: SpaceLabel(name: "Inbox")]))
        let afterSave = try? Data(contentsOf: corruptURL)
        XCTAssertEqual(afterSave, garbage)
    }

    func testLoadDecodesLegacyLabelsOnlyFileAndWorktreeFormat() {
        // Released (pre-fix) format: `{"labels": {...}}`.
        let legacyStore = makeStore()
        try? Data(#"{"labels":{"201":{"name":"Work"}}}"#.utf8).write(to: legacyStore.fileURL)
        let legacy = legacyStore.load()
        XCTAssertEqual(legacy.records[201]?.label.name, "Work")
        XCTAssertNil(legacy.records[201]?.display, "Legacy labels have no display association")

        // Uncommitted worktree format: `{"labels": {...}, "spaceDisplayByID": {...}}`.
        let worktreeStore = makeStore()
        try? Data(
            #"{"labels":{"201":{"name":"Work"}},"spaceDisplayByID":{"201":"display-b"}}"#.utf8
        ).write(to: worktreeStore.fileURL)
        let worktree = worktreeStore.load()
        XCTAssertEqual(worktree.records[201]?.label.name, "Work")
        XCTAssertEqual(worktree.records[201]?.display, "display-b")
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLabelStoreTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
