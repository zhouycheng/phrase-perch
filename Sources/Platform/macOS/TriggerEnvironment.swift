import AppKit
import KeyboardShortcuts

@MainActor
struct TriggerEnvironment {
    var frontmost: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    var mouse: () -> CGPoint = { NSEvent.mouseLocation }
    var modifiers: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]) }
    var primaryTop: () -> CGFloat = { NSScreen.screens.first?.frame.maxY ?? 0 }
    var screens: () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }
    var screenIdentifier: (CGPoint) -> UInt32? = { point in
        (NSScreen.screens.first(where: { $0.frame.contains(point) })?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    var shortcutKey: () -> Int? = { KeyboardShortcuts.getShortcut(for: .togglePhrasePerch)?.carbonKeyCode }
    var keyHeld: (Int) -> Bool = { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var now: () -> ContinuousClock.Instant = { .now }
}
