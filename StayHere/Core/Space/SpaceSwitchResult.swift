import Foundation

public enum SpaceSwitchResult: Equatable {
    case switched
    case alreadyActive
    case unknownSpace
    case unsupportedSpaceKind
    case unsupportedDesktop(index: Int)
    case eventPostFailed(index: Int)
    case switchUnmatched(index: Int, expectedSpaceID: Int, actualSpaceID: Int?)
}
