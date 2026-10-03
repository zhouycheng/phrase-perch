import AppKit
@preconcurrency import ApplicationServices
import KeyboardShortcuts
import Observation
import ServiceManagement
import SwiftUI

@MainActor
struct AuthorizationEnvironment {
    var snapshot: () -> (accessibility: Bool, paste: Bool) = { (AXIsProcessTrusted(), CGPreflightPostEventAccess()) }
    var save: (ConfigurationRepository) async -> Bool = { await $0.flush() }
    var openSettings: () -> Bool = {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    var relaunch: (URL, pid_t) throws -> Void = { url, pid in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            restart_checks=0
            while kill -0 "$1" 2>/dev/null; do
                restart_checks=$((restart_checks + 1))
                [ "$restart_checks" -lt 100 ] || exit 1
                sleep 0.1
            done
            exec /usr/bin/open "$2"
            """, "PhrasePerchRestart", String(pid), url.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
    var systemSettingsIsFrontmost: () -> Bool = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
    }
    var terminate: () -> Void = { NSApp.terminate(nil) }

}
