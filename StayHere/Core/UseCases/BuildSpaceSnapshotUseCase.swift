import Foundation

public final class BuildSpaceSnapshotUseCase {
    private let repository: SpaceRepository

    public init(repository: SpaceRepository) {
        self.repository = repository
    }

    public func execute() -> String {
        repository.snapshotJSON()
    }
}
