import Foundation
import Combine

public struct SpaceState: Equatable {
    public var spaces: [SpaceIdentity] = []
    public var activeSpaceID: Int?
    public var labels: [Int: SpaceLabel] = [:]
    public var desktopNumberBySpaceID: [Int: Int] = [:]
    public var nativeOrderByDisplay: [String: [Int]] = [:]

    public init() {}

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        labels: [Int: SpaceLabel],
        desktopNumberBySpaceID: [Int: Int],
        nativeOrderByDisplay: [String: [Int]]
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.labels = labels
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
    }
}

public final class SpaceStateStore: ObservableObject {
    @Published public private(set) var state = SpaceState()

    public var spaces: [SpaceIdentity] { state.spaces }
    public var activeSpaceID: Int? { state.activeSpaceID }
    public var labels: [Int: SpaceLabel] { state.labels }
    public var desktopNumberBySpaceID: [Int: Int] { state.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { state.nativeOrderByDisplay }

    public init() {}

    public func syncPersistenceState(
        labels: [Int: SpaceLabel]
    ) {
        state = SpaceState(
            spaces: state.spaces,
            activeSpaceID: state.activeSpaceID,
            labels: labels,
            desktopNumberBySpaceID: state.desktopNumberBySpaceID,
            nativeOrderByDisplay: state.nativeOrderByDisplay
        )
    }

    public func applyDerivedState(_ derivedState: SpaceRegistryDerivedState) {
        state = SpaceState(
            spaces: derivedState.spaces,
            activeSpaceID: derivedState.activeSpaceID,
            labels: state.labels,
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
