import Foundation

public final class ReorderSpacesUseCase {
    private let repository: SpaceRepository

    public init(repository: SpaceRepository) {
        self.repository = repository
    }

    public func execute(fromOffsets: IndexSet, toOffset: Int) {
        repository.moveDisplayOrder(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
