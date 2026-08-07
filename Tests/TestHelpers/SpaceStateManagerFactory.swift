import Foundation
import Core

@MainActor
public enum SpaceStateManagerFactory {
    /// Creates a `SpaceStateManager` with sensible defaults for testing.
    ///
    /// - Parameters:
    ///   - cgsBridge: The bridge to use (required — always varies per test).
    ///   - stateStore: An explicit state store (default: fresh `SpaceStateStore()`).
    ///   - store: An explicit `SpaceStore` (default: isolated temp file).
    ///            Pass this when the test needs to pre-populate a store before
    ///            creating the manager.
    ///   - logger: Test logger (default: `NoOpLogger()`).
    ///   - now: Deterministic clock provider for observation-cadence tests
    ///          (default: real wall clock).
    public static func make(
        cgsBridge: some CGSBridgeProtocol,
        stateStore: SpaceStateStore = SpaceStateStore(),
        store: SpaceStore? = nil,
        logger: any Logging = NoOpLogger(),
        now: (() -> Date)? = nil
    ) -> SpaceStateManager {
        let resolvedStore: SpaceStore
        if let store {
            resolvedStore = store
        } else {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpaceStateManagerFactory")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("spaces.json")
            resolvedStore = SpaceStore(fileURL: fileURL)
        }
        let labelStore = now.map { SpaceLabelStore(store: resolvedStore, logger: logger, now: $0) }
        let persistenceCoordinator = SpacePersistenceCoordinator(
            store: resolvedStore,
            labelStore: labelStore,
            logger: logger
        )
        return SpaceStateManager(
            cgsBridge: cgsBridge,
            stateStore: stateStore,
            persistenceCoordinator: persistenceCoordinator,
            orderingService: SpaceOrderingService(),
            nameProvider: SpaceDisplayNameProvider(),
            snapshotBuilder: SpaceSnapshotBuilder(),
            logger: logger
        )
    }
}
