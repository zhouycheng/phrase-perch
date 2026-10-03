import CoreGraphics
import Foundation

struct OperationGate {
    private(set) var activeID: UUID?
    private(set) var generation = 0
    private(set) var mayHaveMutated = false
    mutating func begin() -> UUID? {
        guard activeID == nil else { return nil }
        let id = UUID()
        activeID = id
        mayHaveMutated = false
        return id
    }
    mutating func invalidate() { generation += 1 }
    func isCurrent(_ id: UUID, generation expected: Int) -> Bool {
        activeID == id && generation == expected
    }
    mutating func markWriting(_ id: UUID) { if activeID == id { mayHaveMutated = true } }
    mutating func finish(_ id: UUID) { if activeID == id { activeID = nil } }
}
