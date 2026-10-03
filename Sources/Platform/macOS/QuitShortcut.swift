import AppKit
@preconcurrency import ApplicationServices
import KeyboardShortcuts
import Observation
import ServiceManagement
import SwiftUI

func isCommandQuitShortcut(charactersIgnoringModifiers: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard charactersIgnoringModifiers?.lowercased() == "q" else { return false }
    return modifiers.intersection([.command, .option, .control, .shift]) == .command
}
