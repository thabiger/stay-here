import Foundation

public enum SpaceCycling {
    public static func nextSpaceID(currentSpaceID: Int?, orderedSpaceIDs: [Int]) -> Int? {
        adjacentSpaceID(offset: 1, currentSpaceID: currentSpaceID, orderedSpaceIDs: orderedSpaceIDs)
    }

    public static func previousSpaceID(currentSpaceID: Int?, orderedSpaceIDs: [Int]) -> Int? {
        adjacentSpaceID(offset: -1, currentSpaceID: currentSpaceID, orderedSpaceIDs: orderedSpaceIDs)
    }

    private static func adjacentSpaceID(offset: Int, currentSpaceID: Int?, orderedSpaceIDs: [Int]) -> Int? {
        guard !orderedSpaceIDs.isEmpty else { return nil }

        if let currentSpaceID,
           let index = orderedSpaceIDs.firstIndex(of: currentSpaceID) {
            let nextIndex = (index + offset + orderedSpaceIDs.count) % orderedSpaceIDs.count
            return orderedSpaceIDs[nextIndex]
        }

        return offset > 0 ? orderedSpaceIDs.first : orderedSpaceIDs.last
    }
}
