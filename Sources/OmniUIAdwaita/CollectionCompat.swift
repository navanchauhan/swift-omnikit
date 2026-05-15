import Foundation

public extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where indices.contains(offset) {
            remove(at: offset)
        }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted()
        let elements = moving.map { self[$0] }
        remove(atOffsets: IndexSet(moving))

        var adjustedDestination = destination
        for index in moving where index < destination {
            adjustedDestination -= 1
        }

        let insertIndex = Swift.max(0, Swift.min(adjustedDestination, count))
        insert(contentsOf: elements, at: insertIndex)
    }
}
