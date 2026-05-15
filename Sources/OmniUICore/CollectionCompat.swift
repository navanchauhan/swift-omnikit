import Foundation

public extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().filter { indices.contains($0) }
        guard !moving.isEmpty else { return }
        let elements = moving.map { self[$0] }
        remove(atOffsets: IndexSet(moving))
        let removedBeforeDestination = moving.filter { $0 < destination }.count
        let insertionIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: elements, at: insertionIndex)
    }
}
