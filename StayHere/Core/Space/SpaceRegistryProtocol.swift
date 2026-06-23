import Foundation
import Combine

/// Read-only interface to the current space state.
///
/// UI consumers (StatusBar, Switchers, SpaceObservation) should depend on this
/// protocol to guarantee they cannot mutate space state. Use cases that need
/// write access (rename, reorder, persist) should take ``SpaceStateManager`` directly.
@MainActor
public protocol SpaceRegistryProtocol: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var spaces: [SpaceIdentity] { get }
    var activeSpaceID: Int? { get }
    var labels: [Int: SpaceLabel] { get }
    var displayOrder: [Int] { get }
    var usesCustomDisplayOrder: Bool { get }
    var desktopNumberBySpaceID: [Int: Int] { get }
    var nativeOrderByDisplay: [String: [Int]] { get }

    func name(for spaceID: Int) -> String
    func displayName(for spaceID: Int) -> String
    func namespaceLabel(for spaceID: Int) -> String
    func space(for spaceID: Int) -> SpaceIdentity?
    func isSwitchableSpace(_ spaceID: Int) -> Bool
    func orderedSpaceIDs() -> [Int]
    func switchableOrderedSpaceIDs() -> [Int]
    func activeNameSummary() -> String
    func activeName() -> String
}
