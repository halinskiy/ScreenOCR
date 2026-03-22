import Cocoa

final class PermissionManager {

    // MARK: Screen Recording

    static var hasScreenRecordingPermission: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            showRestartRequiredAlert()
        }
        return granted
    }

    static func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "ScreenOCR needs Screen Recording permission to capture screen regions for text extraction.\n\nPlease grant access in System Settings → Privacy & Security → Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Accessibility (required for global hotkeys)

    static var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func showAccessibilityDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "ScreenOCR needs Accessibility permission for global hotkeys (⌘⇧1/2) to work everywhere — over menus, modals, and other apps.\n\nPlease grant access in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Common

    static func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Перезапустите приложение"
        alert.informativeText = "После выдачи разрешения нужно перезапустить приложение через меню Apple → Завершить и открыть заново."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "ОК")
        alert.runModal()
    }
}
