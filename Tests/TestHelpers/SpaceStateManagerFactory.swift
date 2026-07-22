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
    public static func make(
        cgsBridge: some CGSBridgeProtocol,
        stateStore: SpaceStateStore = SpaceStateStore(),
        store: SpaceStore? = nil,
        logger: any Logging = NoOpLogger()
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
        let persistenceCoordinator = SpacePersistenceCoordinator(
            store: resolvedStore,
            labelStore: nil,
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
