import Foundation

@MainActor
public final class BuildSpaceSnapshotUseCase {
    private let repository: SpaceStateManager

    public init(repository: SpaceStateManager) {
        self.repository = repository
    }

    public func execute() -> String {
        repository.snapshotJSON()
    }
}
