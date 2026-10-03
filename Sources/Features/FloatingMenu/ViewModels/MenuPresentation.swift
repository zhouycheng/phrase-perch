import AppKit
import QuartzCore

struct MenuPresentation {
    enum Phase { case hidden, showing, visible, hiding }
    private(set) var generation = 0
    private(set) var phase = Phase.hidden
    var presented: Bool { phase == .showing || phase == .visible }
    mutating func show() -> Int {
        generation += 1
        phase = .showing
        return generation
    }
    mutating func hide() -> Int {
        generation += 1
        phase = .hiding
        return generation
    }
    mutating func finishShow(_ token: Int) -> Bool {
        guard token == generation, phase == .showing else { return false }
        phase = .visible
        return true
    }
    mutating func finishHide(_ token: Int) -> Bool {
        guard token == generation, phase == .hiding else { return false }
        phase = .hidden
        return true
    }
}
