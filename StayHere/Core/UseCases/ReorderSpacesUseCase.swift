import Foundation

public final class ReorderSpacesUseCase {
    private let repository: SpaceStateManager

    public init(repository: SpaceStateManager) {
        self.repository = repository
    }

    public func execute(fromOffsets: IndexSet, toOffset: Int) {
        repository.moveDisplayOrder(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
