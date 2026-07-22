import Foundation

@MainActor
public final class ReorderSpacesUseCase {
    private let reorderer: any SpaceReordering

    public init(reorderer: any SpaceReordering) {
        self.reorderer = reorderer
    }

    public func execute(fromOffsets: IndexSet, toOffset: Int) {
        reorderer.moveDisplayOrder(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
