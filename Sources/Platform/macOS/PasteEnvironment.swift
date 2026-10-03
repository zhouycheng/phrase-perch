import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

@MainActor
struct PasteEnvironment {
    var targetIsCurrent: (NSRunningApplication) -> Bool = {
        !$0.isTerminated && NSWorkspace.shared.frontmostApplication?.isEqual($0) == true
    }
    var modifiersReleased: () -> Bool = {
        NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }
    var authorized: () -> Bool = { CGPreflightPostEventAccess() && !IsSecureEventInputEnabled() }
    var copy: (String) throws -> Int = { try ClipboardService.copy($0) }
    var clipboardRevision: () -> Int = { NSPasteboard.general.changeCount }
    var dispatch: () -> Bool = { PasteEventDispatcher.dispatch() }
}
