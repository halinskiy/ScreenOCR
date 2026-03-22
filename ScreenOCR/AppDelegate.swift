import Cocoa

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayWindow()
    private var eventTap: CFMachPort?
    private var isCapturing = false
    private var isSVGMode = false
    private var previousApp: NSRunningApplication?
    private var preCapturedImages: [(displayID: CGDirectDisplayID, bounds: CGRect, image: CGImage)] = []

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()

        if !PermissionManager.hasScreenRecordingPermission {
            PermissionManager.requestScreenRecordingPermission()
        }

        if !PermissionManager.hasAccessibilityPermission {
            PermissionManager.requestAccessibilityPermission()
        }

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

        let ocrItem = NSMenuItem(title: "OCR Capture", action: #selector(startOCRCapture), keyEquivalent: "")
        ocrItem.target = self
        ocrItem.keyEquivalent = "1"
        ocrItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(ocrItem)

        let svgItem = NSMenuItem(title: "SVG Capture", action: #selector(startSVGCapture), keyEquivalent: "")
        svgItem.target = self
        svgItem.keyEquivalent = "2"
        svgItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(svgItem)

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

        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: Global Hotkey (CGEvent Tap)

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()

                guard type == .keyDown else {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = appDelegate.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let hasExtra = !flags.intersection([.maskControl, .maskAlternate]).isEmpty

                if hasCmd && hasShift && !hasExtra {
                    if keyCode == 18 { // ⌘⇧1 — OCR Capture
                        DispatchQueue.main.async { appDelegate.startOCRCapture() }
                        return nil
                    }
                    if keyCode == 19 { // ⌘⇧2 — SVG Capture
                        DispatchQueue.main.async { appDelegate.startSVGCapture() }
                        return nil
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("ScreenOCR: Failed to create CGEvent tap — Accessibility permission required")
            DispatchQueue.main.async {
                PermissionManager.showAccessibilityDeniedAlert()
            }
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
                    width: rect.width * scale,
                    height: rect.height * scale
                )
                return image.cropping(to: localRect)
            }
        }
        return nil
    }

    // MARK: Capture Flow

    @objc private func startOCRCapture() {
        // Switch mode on the fly if already capturing
        if isCapturing {
            guard isSVGMode else { return }
            isSVGMode = false
            overlay.switchToOCRMode()
            overlay.preScanWordBoxes(level: .fast, screenImages: screenImagesForOverlay)
            updateStatusLabel(nil)
            ToastWindow.show("OCR Mode")
            return
        }

        guard PermissionManager.hasScreenRecordingPermission else {
            PermissionManager.showPermissionDeniedAlert()
            return
        }

        preCaptureScreens()

        isCapturing = true
        isSVGMode = false
        previousApp = NSWorkspace.shared.frontmostApplication

        overlay.showFast(screenImages: screenImagesForOverlay, onComplete: { [weak self] cgRect in
            self?.handleCaptureComplete(cgRect)
        }, onCancel: { [weak self] in
            self?.isCapturing = false
            self?.preCapturedImages = []
            self?.smartReturnFocus()
        })
    }

    @objc private func startSVGCapture() {
        // Switch mode on the fly if already capturing
        if isCapturing {
            guard !isSVGMode else { return }
            isSVGMode = true
            overlay.switchToSVGMode()
            updateStatusLabel("SVG")
            ToastWindow.show("SVG Mode")
            SVGExtractor.getSVGBoundingBoxes(from: previousApp) { [weak self] boxes in
                self?.overlay.setSVGBoxes(boxes)
            }
            return
        }

        guard PermissionManager.hasScreenRecordingPermission else {
            PermissionManager.showPermissionDeniedAlert()
            return
        }

        preCaptureScreens()

        isCapturing = true
        isSVGMode = true
        let browserApp = NSWorkspace.shared.frontmostApplication
        previousApp = browserApp
        updateStatusLabel("SVG")
        ToastWindow.show("SVG Mode")

        overlay.showForSVG(screenImages: screenImagesForOverlay, onComplete: { [weak self] cgRect in
            self?.handleCaptureComplete(cgRect)
        }, onCancel: { [weak self] in
            self?.isCapturing = false
            self?.preCapturedImages = []
            self?.updateStatusLabel(nil)
            self?.smartReturnFocus()
        })

        SVGExtractor.getSVGBoundingBoxes(from: browserApp) { [weak self] boxes in
            self?.overlay.setSVGBoxes(boxes)
        }
    }

    /// Unified completion handler — routes to OCR or SVG based on current mode
    private func handleCaptureComplete(_ cgRect: CGRect) {
        if isSVGMode {
            updateStatusLabel(nil)
            performSVGExtraction(on: cgRect)
        } else {
            performPreCapturedOCR(on: cgRect)
        }
    }

    // MARK: OCR from pre-captured image (instant — no post-dismiss delay)

    private func performPreCapturedOCR(on rect: CGRect) {
        isCapturing = false

        guard let cropped = cropPreCapture(to: rect) else {
            ToastWindow.show("Capture failed")
            preCapturedImages = []
            smartReturnFocus()
            return
        }

        preCapturedImages = [] // release memory

        OCREngine.recognizeText(in: cropped) { [weak self] text in
            guard let self = self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ToastWindow.show("No text found")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trimmed, forType: .string)
                ToastWindow.show("Copied")
            }
            self.smartReturnFocus()
        }
    }

    private func performSVGExtraction(on rect: CGRect) {
        let browserApp = previousApp

        SVGExtractor.extractSVGs(in: rect, from: browserApp) { [weak self] svgs in
            guard let self = self else { return }
            self.isCapturing = false

            if svgs.isEmpty {
                ToastWindow.show("No SVGs found")
            } else {
                SVGExtractor.copyToClipboard(svgs)
                let label = svgs.count == 1 ? "1 SVG copied" : "\(svgs.count) SVGs copied"
                ToastWindow.show(label)
            }

            self.smartReturnFocus()
        }
    }

    // MARK: Focus management

    private func smartReturnFocus() {
        updateStatusLabel(nil)
        // Only return focus if our app is still frontmost (user hasn't alt-tabbed away)
        if NSApp.isActive {
            previousApp?.activate()
        }
        previousApp = nil
    }

    // MARK: Menu Actions

    @objc private func restartApp() {
        let executablePath = Bundle.main.executablePath!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
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
            var hex = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            hex = hex.replacingOccurrences(of: "#", with: "")
            if hex.count == 6, UInt64(hex, radix: 16) != nil {
                UserDefaults.standard.set(hex.uppercased(), forKey: "highlightColorHex")
                rebuildMenu()
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSColor HEX Extension

extension NSColor {
    convenience init(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexStr = hexStr.replacingOccurrences(of: "#", with: "")
        guard hexStr.count == 6, let val = UInt64(hexStr, radix: 16) else {
            self.init(red: 1, green: 0.84, blue: 0.04, alpha: 1)
            return
        }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
