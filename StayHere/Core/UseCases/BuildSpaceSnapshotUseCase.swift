import Foundation

@MainActor
public final class BuildSpaceSnapshotUseCase {
    private let builder: any SpaceSnapshotBuilding

    public init(builder: any SpaceSnapshotBuilding) {
        self.builder = builder
    }

    public func execute() -> String {
        builder.snapshotJSON()
    }
}
