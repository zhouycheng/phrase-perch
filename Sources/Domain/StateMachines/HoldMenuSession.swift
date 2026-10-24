import CoreGraphics
import Foundation

struct HoldMenuSession {
    static let modifierReleaseTimeout: Duration = .seconds(1)
    enum Trigger: Equatable { case modifier, shortcut }
    enum Phase: Equatable { case idle, checking, choosing, waitingForModifiers, inserting }
    enum ModifierAction: Equatable { case begin, release, cancel, none }
    private(set) var id: UUID?
    private(set) var trigger: Trigger?
    private(set) var phase = Phase.idle

    func modifierAction(current: UInt, previous: UInt, configured: UInt, shortcutModifiers: UInt?) -> ModifierAction {
        if trigger == .shortcut {
            return .none
        }
        if trigger == .modifier, phase == .checking || phase == .choosing {
            return current == 0 ? .release : (current == configured ? .none : .cancel)
        }
        return current == configured && previous & configured == 0 ? .begin : .none
    }

    mutating func begin(_ trigger: Trigger) -> UUID? {
        guard phase == .idle else { return nil }
        let token = UUID()
        id = token
        self.trigger = trigger
        phase = .checking
        return token
    }
    func isCurrent(_ token: UUID) -> Bool { id == token && phase != .idle }
    mutating func show(_ token: UUID) -> Bool {
        guard isCurrent(token), phase == .checking else { return false }
        phase = .choosing
        return true
    }
    mutating func release(_ source: Trigger, selection: UUID?) -> UUID? {
        guard source == .modifier else { return nil }
        return select(source, selection: selection)
    }
    mutating func select(_ source: Trigger, selection: UUID?) -> UUID? {
        guard trigger == source, phase == .checking || phase == .choosing else { return nil }
        guard phase == .choosing, selection != nil, let token = id else {
            cancel()
            return nil
        }
        phase = .waitingForModifiers
        return token
    }
    mutating func commit(_ token: UUID) -> Bool {
        guard isCurrent(token), phase == .waitingForModifiers else { return false }
        phase = .inserting
        return true
    }
    mutating func cancel() {
        id = nil
        trigger = nil
        phase = .idle
    }
}
