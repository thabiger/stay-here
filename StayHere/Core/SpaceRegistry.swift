import Foundation
import Combine

public final class SpaceRegistry: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()

    public var spaces: [SpaceIdentity] { repository.spaces }
    public var activeSpaceID: Int? { repository.activeSpaceID }
    public var labels: [Int: SpaceLabel] { repository.labels }
    public var displayOrder: [Int] { repository.displayOrder }
    public var usesCustomDisplayOrder: Bool { repository.usesCustomDisplayOrder }
    public var desktopNumberBySpaceID: [Int: Int] { repository.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { repository.nativeOrderByDisplay }

    private let repository: SpaceRepository
    private var repositoryObserver: AnyCancellable?

    public init(repository: SpaceRepository) {
        self.repository = repository
        bindRepository()
    }

    public convenience init(
        store: SpaceStore = SpaceStore(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        labelStore: SpaceLabelStore? = nil,
        logger: any Logging
    ) {
        let repository = SpaceRepository(
            store: store,
            cgsBridge: cgsBridge,
            labelStore: labelStore,
            logger: logger
        )
        self.init(repository: repository)
    }

    public func name(for spaceID: Int) -> String {
        repository.name(for: spaceID)
    }

    public func displayName(for spaceID: Int) -> String {
        repository.displayName(for: spaceID)
    }

    public func namespaceLabel(for spaceID: Int) -> String {
        repository.namespaceLabel(for: spaceID)
    }

    public func space(for spaceID: Int) -> SpaceIdentity? {
        repository.space(for: spaceID)
    }

    public func isSwitchableSpace(_ spaceID: Int) -> Bool {
        repository.isSwitchableSpace(spaceID)
    }

    public func orderedSpaceIDs() -> [Int] {
        repository.orderedSpaceIDs()
    }

    public func switchableOrderedSpaceIDs() -> [Int] {
        repository.switchableOrderedSpaceIDs()
    }

    public func activeNameSummary() -> String {
        repository.activeNameSummary()
    }

    public func activeName() -> String {
        repository.activeName()
    }

    private func bindRepository() {
        repositoryObserver = repository.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
