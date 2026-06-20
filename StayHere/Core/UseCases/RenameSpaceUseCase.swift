import Foundation

public final class RenameSpaceUseCase {
    private let repository: SpaceRepository

    public init(repository: SpaceRepository) {
        self.repository = repository
    }

    public func execute(spaceID: Int, name: String) {
        repository.rename(spaceID: spaceID, name: name)
    }
}
