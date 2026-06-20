import Foundation
import Combine

public final class SpaceStateStore: ObservableObject {
    @Published public private(set) var spaces: [SpaceIdentity] = []
    @Published public private(set) var activeSpaceID: Int?
    @Published public private(set) var labels: [Int: SpaceLabel] = [:]
    @Published public private(set) var displayOrder: [Int] = []
    @Published public private(set) var usesCustomDisplayOrder: Bool = false
    @Published public private(set) var desktopNumberBySpaceID: [Int: Int] = [:]
    @Published public private(set) var nativeOrderByDisplay: [String: [Int]] = [:]

    public init() {}

    public func syncPersistenceState(
        labels: [Int: SpaceLabel],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool
    ) {
        self.labels = labels
        self.displayOrder = displayOrder
        self.usesCustomDisplayOrder = usesCustomDisplayOrder
    }

    public func applyDerivedState(_ derivedState: SpaceRegistryDerivedState) {
        spaces = derivedState.spaces
        activeSpaceID = derivedState.activeSpaceID
        nativeOrderByDisplay = derivedState.nativeOrderByDisplay
        desktopNumberBySpaceID = derivedState.desktopNumberBySpaceID
    }

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        SpaceSwitchSnapshot(
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            nativeOrderByDisplay: nativeOrderByDisplay
        )
    }
}
