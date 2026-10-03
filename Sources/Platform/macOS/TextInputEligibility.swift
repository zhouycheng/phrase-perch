import AppKit
import ApplicationServices
import Carbon
import OSLog
import Observation

func isOrdinaryTextInput(role: String?, subrole: String?, enabled: Bool?) -> Bool {
    // AppKit NSTextView omits AXEnabled. Missing is not the same as disabled;
    // prepare still requires a positively writable text attribute below.
    enabled != false && subrole != kAXSecureTextFieldSubrole as String
        && [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role ?? "")
}
