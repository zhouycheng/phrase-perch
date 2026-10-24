import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

enum TextInputEligibility {
    static func supportsPasteAdapter(_ bundleIdentifier: String?) -> Bool {
        ["com.apple.Safari", "com.openai.chat", "com.openai.codex"].contains(bundleIdentifier ?? "")
    }
}

func isOrdinaryTextInput(role: String?, subrole: String?, enabled: Bool?) -> Bool {
    // AppKit NSTextView may omit AXEnabled; paste eligibility also checks the editor's capabilities.
    enabled != false && subrole != kAXSecureTextFieldSubrole as String
        && [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role ?? "")
}
