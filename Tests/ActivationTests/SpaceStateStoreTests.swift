import Combine
import XCTest
import Core

final class SpaceStateStoreTests: XCTestCase {
    func testApplyDerivedStatePublishesOnlyOnChange() {
        let store = SpaceStateStore()
        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.objectWillChange.sink { _ in
            publishCount += 1
        }
        .store(in: &cancellables)

        let derived = SpaceRegistryDerivedState(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeSpaceID: 101,
            nativeOrderByDisplay: ["display-a": [101]],
            desktopNumberBySpaceID: [101: 1]
        )

        store.applyDerivedState(derived)
        store.applyDerivedState(derived)
        XCTAssertEqual(publishCount, 1)

        store.applyDerivedState(
            SpaceRegistryDerivedState(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeSpaceID: 102,
                nativeOrderByDisplay: ["display-a": [101]],
                desktopNumberBySpaceID: [101: 1]
            )
        )
        XCTAssertEqual(publishCount, 2)

        XCTAssertNotNil(cancellables)
    }

    func testApplyDerivedStateCarriesStaleFlag() {
        let store = SpaceStateStore()

        store.applyDerivedState(
            SpaceRegistryDerivedState(
                spaces: [],
                activeSpaceID: nil,
                nativeOrderByDisplay: [:],
                desktopNumberBySpaceID: [:],
                isStaleSnapshot: true
            )
        )
        XCTAssertTrue(store.isStaleSnapshot)

        store.applyDerivedState(
            SpaceRegistryDerivedState(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeSpaceID: 101,
                nativeOrderByDisplay: ["display-a": [101]],
                desktopNumberBySpaceID: [101: 1]
            )
        )
        XCTAssertFalse(store.isStaleSnapshot)
    }

    func testSyncPersistenceStatePublishesOnlyOnChange() {
        let store = SpaceStateStore()
        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.objectWillChange.sink { _ in
            publishCount += 1
        }
        .store(in: &cancellables)

        let workLabels: [Int: SpaceLabel] = [101: SpaceLabel(name: "Work")]
        store.syncPersistenceState(labels: workLabels)
        store.syncPersistenceState(labels: workLabels)
        XCTAssertEqual(publishCount, 1)

        store.syncPersistenceState(labels: [101: SpaceLabel(name: "Home")])
        XCTAssertEqual(publishCount, 2)

        XCTAssertNotNil(cancellables)
    }
}
