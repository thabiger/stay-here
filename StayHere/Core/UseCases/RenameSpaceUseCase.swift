import Foundation

@MainActor
public final class RenameSpaceUseCase {
    private let renamer: any SpaceRenaming

    public init(renamer: any SpaceRenaming) {
        self.renamer = renamer
    }

    public func execute(spaceID: Int, name: String) {
        renamer.rename(spaceID: spaceID, name: name)
    }
}
