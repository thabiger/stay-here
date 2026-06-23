import Foundation
import Combine

public struct SpaceState: Equatable {
    public var spaces: [SpaceIdentity] = []
    public var activeSpaceID: Int?
    public var labels: [Int: SpaceLabel] = [:]
    public var displayOrder: [Int] = []
    public var usesCustomDisplayOrder: Bool = false
    public var desktopNumberBySpaceID: [Int: Int] = [:]
    public var nativeOrderByDisplay: [String: [Int]] = [:]

    public init() {}

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        labels: [Int: SpaceLabel],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool,
        desktopNumberBySpaceID: [Int: Int],
        nativeOrderByDisplay: [String: [Int]]
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.labels = labels
        self.displayOrder = displayOrder
        self.usesCustomDisplayOrder = usesCustomDisplayOrder
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
    }
}

public final class SpaceStateStore: ObservableObject {
    @Published public private(set) var state = SpaceState()

    public var spaces: [SpaceIdentity] { state.spaces }
    public var activeSpaceID: Int? { state.activeSpaceID }
    public var labels: [Int: SpaceLabel] { state.labels }
    public var displayOrder: [Int] { state.displayOrder }
    public var usesCustomDisplayOrder: Bool { state.usesCustomDisplayOrder }
    public var desktopNumberBySpaceID: [Int: Int] { state.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { state.nativeOrderByDisplay }

    public init() {}

    public func syncPersistenceState(
        labels: [Int: SpaceLabel],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool
    ) {
        state = SpaceState(
            spaces: state.spaces,
            activeSpaceID: state.activeSpaceID,
            labels: labels,
            displayOrder: displayOrder,
            usesCustomDisplayOrder: usesCustomDisplayOrder,
            desktopNumberBySpaceID: state.desktopNumberBySpaceID,
            nativeOrderByDisplay: state.nativeOrderByDisplay
        )
    }

    public func applyDerivedState(_ derivedState: SpaceRegistryDerivedState) {
        state = SpaceState(
            spaces: derivedState.spaces,
            activeSpaceID: derivedState.activeSpaceID,
            labels: state.labels,
            displayOrder: state.displayOrder,
            usesCustomDisplayOrder: state.usesCustomDisplayOrder,
            desktopNumberBySpaceID: derivedState.desktopNumberBySpaceID,
            nativeOrderByDisplay: derivedState.nativeOrderByDisplay
        )
    }

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        SpaceSwitchSnapshot(
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            nativeOrderByDisplay: nativeOrderByDisplay
        )
    }
}
