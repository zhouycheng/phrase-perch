import Foundation
import Observation
import OSLog

@MainActor @Observable
final class InteractionDiagnostics {
    struct Entry: Identifiable {
        let id: UUID
        let started: Date
        var stage: String
        var detail: String
        var anchor = ""
        var screenID: UInt32?
        var readyAfter: TimeInterval?
        var elapsed: TimeInterval = 0
    }
    private(set) var entries: [Entry] = []
    private let log = Logger(subsystem: "local.PhrasePerch", category: "interaction")
    func record(_ id: UUID, stage: String, detail: String = "", anchor: String? = nil, screenID: UInt32? = nil) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].stage = stage
            entries[index].detail = detail
            entries[index].elapsed = Date().timeIntervalSince(entries[index].started)
            if let anchor {
                entries[index].anchor = anchor
                entries[index].readyAfter = entries[index].elapsed
            }
            if let screenID { entries[index].screenID = screenID }
        } else {
            entries.insert(Entry(id: id, started: Date(), stage: stage, detail: detail,
                anchor: anchor ?? "", screenID: screenID), at: 0)
            entries = Array(entries.prefix(20))
        }
        log.info("Session \(id.uuidString, privacy: .public) stage=\(stage, privacy: .public) detail=\(detail, privacy: .public)")
    }
}
