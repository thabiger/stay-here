import Foundation

@MainActor
public final class RenameSpaceUseCase {
    private let repository: SpaceStateManager

    public init(repository: SpaceStateManager) {
        self.repository = repository
    }

    public func execute(spaceID: Int, name: String) {
        repository.rename(spaceID: spaceID, name: name)
    }
}
