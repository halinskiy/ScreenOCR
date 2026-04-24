import Cocoa
import Sparkle

// MARK: - Capture Mode

enum CaptureMode { case ocr, svg, hex }

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayWindow()
    private var eventTap: CFMachPort?
    private var isCapturing = false
    private var currentMode: CaptureMode = .ocr
    private var previousApp: NSRunningApplication?
    private var preCapturedImages: [(displayID: CGDirectDisplayID, bounds: CGRect, image: CGImage)] = []

    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        WelcomeWindowController.showIfNeeded()
        // Always register with ScreenCaptureKit so app appears in Screen & System Audio Recording list.
        // On macOS 15+, CGPreflightScreenCaptureAccess() may return true without registering in the new TCC list.
        PermissionManager.registerWithScreenCaptureKit()
        if !PermissionManager.hasScreenRecordingPermission { PermissionManager.requestScreenRecordingPermission() }
        if !PermissionManager.hasAccessibilityPermission { PermissionManager.requestAccessibilityPermission() }
        installEventTap()
    }

    // MARK: Status Item & Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Screen OCR") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            } else {
                button.title = "OCR"
            }
        }
        rebuildMenu()
    }

    private func updateStatusLabel(_ label: String?) {
        statusItem.button?.title = label.map { " \($0)" } ?? ""
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = 280

        let captureItem = NSMenuItem(title: "Capture  ⌘⇧1", action: #selector(handleCaptureHotkey), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(.separator())

        let permItem = NSMenuItem(title: "Permissions & Welcome…", action: #selector(showWelcome), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(.separator())

        let colorItem = NSMenuItem(title: "Highlight Color", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu()
        let colors: [(String, String)] = [
            ("Yellow", "FFD60A"), ("Green", "30D158"), ("Blue", "0A84FF"),
            ("Orange", "FF9F0A"), ("Pink", "FF375F"), ("Purple", "BF5AF2"),
        ]
        let currentHex = UserDefaults.standard.string(forKey: "highlightColorHex") ?? "FFD60A"
        for (name, hex) in colors {
            let item = NSMenuItem(title: name, action: #selector(setHighlightColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hex
            item.state = (hex == currentHex) ? .on : .off
            let swatch = NSImage(size: NSSize(width: 12, height: 12))
            swatch.lockFocus()
            NSColor(hex: hex).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
            swatch.unlockFocus()
            item.image = swatch
            colorSubmenu.addItem(item)
        }
        colorSubmenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom HEX...", action: #selector(setCustomHighlightColor), keyEquivalent: "")
        customItem.target = self
        colorSubmenu.addItem(customItem)
        colorItem.submenu = colorSubmenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "u")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: Global Hotkey

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let app = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                guard type == .keyDown else {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = app.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let hasExtra = !flags.intersection([.maskControl, .maskAlternate]).isEmpty
                if hasCmd && hasShift && !hasExtra && keyCode == 18 {
                    DispatchQueue.main.async { app.handleCaptureHotkey() }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("ScreenOCR: Failed to create CGEvent tap — Accessibility permission required")
            DispatchQueue.main.async { PermissionManager.showAccessibilityDeniedAlert() }
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Capture Flow

    @objc func handleCaptureHotkey() {
        if isCapturing {
            cycleMode()
        } else {
            currentMode = .ocr
            startCapture()
        }
    }

    private func cycleMode() {
        switch currentMode {
        case .ocr:
            currentMode = .hex
            overlay.switchToHEXMode { [weak self] hex in
                self?.handleColorPicked(hex)
            }
            updateStatusLabel("HEX")
            ToastWindow.show("Color Picker")
        case .hex:
            currentMode = .svg
            overlay.switchToSVGMode()
            updateStatusLabel("SVG")
            ToastWindow.show("SVG Mode")
            SVGExtractor.getSVGBoundingBoxes(from: previousApp) { [weak self] boxes in
                self?.overlay.setSVGBoxes(boxes)
            }
        case .svg:
            currentMode = .ocr
            overlay.switchToOCRMode()
            overlay.preScanWordBoxes(level: .fast, screenImages: screenImagesForOverlay)
            updateStatusLabel(nil)
            ToastWindow.show("OCR Mode")
        }
    }

    private func startCapture() {
        guard PermissionManager.hasScreenRecordingPermission else {
            PermissionManager.showPermissionDeniedAlert()
            return
        }
        preCaptureScreens()
        isCapturing = true
        previousApp = NSWorkspace.shared.frontmostApplication

        switch currentMode {
        case .ocr:
            overlay.showFast(screenImages: screenImagesForOverlay, onComplete: { [weak self] rect in
                self?.handleCaptureComplete(rect)
            }, onCancel: { [weak self] in
                self?.cancelCapture()
            })

        case .svg:
            updateStatusLabel("SVG")
            overlay.showForSVG(screenImages: screenImagesForOverlay, onComplete: { [weak self] rect in
                self?.handleCaptureComplete(rect)
            }, onCancel: { [weak self] in
                self?.updateStatusLabel(nil)
                self?.cancelCapture()
            })
            SVGExtractor.getSVGBoundingBoxes(from: previousApp) { [weak self] boxes in
                self?.overlay.setSVGBoxes(boxes)
            }

        case .hex:
            updateStatusLabel("HEX")
            overlay.showForHEX(screenImages: screenImagesForOverlay, onColorPicked: { [weak self] hex in
                self?.handleColorPicked(hex)
            }, onCancel: { [weak self] in
                self?.updateStatusLabel(nil)
                self?.cancelCapture()
            })
        }
    }

    private func cancelCapture() {
        isCapturing = false
        preCapturedImages = []
        smartReturnFocus()
    }

    private func handleColorPicked(_ hex: String) {
        isCapturing = false
        updateStatusLabel(nil)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        ToastWindow.show(hex)
        smartReturnFocus()
    }

    private func handleCaptureComplete(_ cgRect: CGRect) {
        switch currentMode {
        case .svg: performSVGExtraction(on: cgRect)
        case .ocr, .hex: performPreCapturedOCR(on: cgRect)
        }
    }

    // MARK: Pre-capture

    private func preCaptureScreens() {
        preCapturedImages = []
        for screen in NSScreen.screens {
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let image = CGDisplayCreateImage(displayID) {
                preCapturedImages.append((displayID, CGDisplayBounds(displayID), image))
            }
        }
    }

    private var screenImagesForOverlay: [(displayID: CGDirectDisplayID, image: CGImage)] {
        preCapturedImages.map { ($0.displayID, $0.image) }
    }

    private func cropPreCapture(to rect: CGRect) -> CGImage? {
        for (_, bounds, image) in preCapturedImages {
            if bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) {
                let scale = CGFloat(image.width) / bounds.width
                let localRect = CGRect(
                    x: (rect.origin.x - bounds.origin.x) * scale,
                    y: (rect.origin.y - bounds.origin.y) * scale,
                    width: rect.width * scale, height: rect.height * scale
                )
                return image.cropping(to: localRect)
            }
        }
        return nil
    }

    // MARK: OCR

    private func performPreCapturedOCR(on rect: CGRect) {
        isCapturing = false
        guard let cropped = cropPreCapture(to: rect) else {
            ToastWindow.show("Capture failed")
            preCapturedImages = []
            smartReturnFocus()
            return
        }
        preCapturedImages = []
        OCREngine.recognizeText(in: cropped) { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { ToastWindow.show("No text found") }
            else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trimmed, forType: .string)
                ToastWindow.show("Copied")
            }
            self.smartReturnFocus()
        }
    }

    // MARK: SVG

    private func performSVGExtraction(on rect: CGRect) {
        let browserApp = previousApp
        SVGExtractor.extractSVGs(in: rect, from: browserApp) { [weak self] svgs in
            guard let self else { return }
            self.isCapturing = false
            if svgs.isEmpty { ToastWindow.show("No SVGs found") }
            else {
                SVGExtractor.copyToClipboard(svgs)
                ToastWindow.show(svgs.count == 1 ? "1 SVG copied" : "\(svgs.count) SVGs copied")
            }
            self.smartReturnFocus()
        }
    }

    // MARK: Focus

    private func smartReturnFocus() {
        updateStatusLabel(nil)
        if NSApp.isActive { previousApp?.activate() }
        previousApp = nil
    }

    // MARK: Menu Actions

    @objc private func showWelcome() {
        WelcomeWindowController.show()
    }

    @objc private func restartApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Bundle.main.executablePath!)
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func setHighlightColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        UserDefaults.standard.set(hex, forKey: "highlightColorHex")
        rebuildMenu()
    }

    @objc private func setCustomHighlightColor() {
        let alert = NSAlert()
        alert.messageText = "Enter HEX Color"
        alert.informativeText = "Example: FF9F0A"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: "highlightColorHex") ?? "FFD60A"
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            var hex = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
            if hex.count == 6, UInt64(hex, radix: 16) != nil {
                UserDefaults.standard.set(hex.uppercased(), forKey: "highlightColorHex")
                rebuildMenu()
            }
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - NSColor HEX Extension

extension NSColor {
    convenience init(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hexStr.count == 6, let val = UInt64(hexStr, radix: 16) else {
            self.init(red: 1, green: 0.84, blue: 0.04, alpha: 1); return
        }
        self.init(
            red:   CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( val        & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
