import Foundation
import Combine

public struct SpaceState: Equatable {
    public var spaces: [SpaceIdentity] = []
    public var activeSpaceID: Int?
    public var labels: [Int: SpaceLabel] = [:]
    public var desktopNumberBySpaceID: [Int: Int] = [:]
    public var nativeOrderByDisplay: [String: [Int]] = [:]
    public var isStaleSnapshot: Bool = false

    public init() {}

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        labels: [Int: SpaceLabel],
        desktopNumberBySpaceID: [Int: Int],
        nativeOrderByDisplay: [String: [Int]],
        isStaleSnapshot: Bool = false
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.labels = labels
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
        self.isStaleSnapshot = isStaleSnapshot
    }
}

public final class SpaceStateStore: ObservableObject {
    @Published public private(set) var state = SpaceState()

    public var spaces: [SpaceIdentity] { state.spaces }
    public var activeSpaceID: Int? { state.activeSpaceID }
    public var labels: [Int: SpaceLabel] { state.labels }
    public var desktopNumberBySpaceID: [Int: Int] { state.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { state.nativeOrderByDisplay }
    public var isStaleSnapshot: Bool { state.isStaleSnapshot }

    public init() {}

    public func syncPersistenceState(
        labels: [Int: SpaceLabel]
    ) {
        let nextState = SpaceState(
            spaces: state.spaces,
            activeSpaceID: state.activeSpaceID,
            labels: labels,
            desktopNumberBySpaceID: state.desktopNumberBySpaceID,
            nativeOrderByDisplay: state.nativeOrderByDisplay,
            isStaleSnapshot: state.isStaleSnapshot
        )
        guard nextState != state else { return }
        state = nextState
    }

    public func applyDerivedState(_ derivedState: SpaceRegistryDerivedState) {
        let nextState = SpaceState(
            spaces: derivedState.spaces,
            activeSpaceID: derivedState.activeSpaceID,
            labels: state.labels,
            desktopNumberBySpaceID: derivedState.desktopNumberBySpaceID,
            nativeOrderByDisplay: derivedState.nativeOrderByDisplay,
            isStaleSnapshot: derivedState.isStaleSnapshot
        )
        guard nextState != state else { return }
        state = nextState
    }

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        SpaceSwitchSnapshot(
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            nativeOrderByDisplay: nativeOrderByDisplay,
            isStaleSnapshot: isStaleSnapshot
        )
    }
}
