import Cocoa

// MARK: - Pill Button

private final class PillButton: NSButton {

    enum Style { case primary, secondary }

    private let btnStyle: Style
    private var hovered = false
    private var pressed = false

    init(_ title: String, style: Style, target: AnyObject?, action: Selector) {
        self.btnStyle = style
        super.init(frame: .zero)
        self.title      = title
        self.target     = target
        self.action     = action
        self.isBordered = false
        self.font       = NSFont.systemFont(ofSize: 14, weight: .medium)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: 34).isActive = true
        self.widthAnchor .constraint(greaterThanOrEqualToConstant: 140).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: font!]).width
        return NSSize(width: max(w + 40, 140), height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { pressed = true;  needsDisplay = true; super.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent)      { pressed = false; needsDisplay = true; super.mouseUp(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        let r    = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        let a: CGFloat = pressed ? 0.65 : (hovered ? 0.88 : 1.0)

        switch btnStyle {
        case .primary:
            NSColor.controlAccentColor.withAlphaComponent(a).setFill()
            path.fill()
        case .secondary:
            NSColor.labelColor.withAlphaComponent(hovered ? 0.10 : 0.07).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let fg: NSColor = btnStyle == .primary ? .white : .labelColor
        let f           = font ?? NSFont.systemFont(ofSize: 14, weight: .medium)
        let str = NSAttributedString(string: title, attributes: [
            .font: f,
            .foregroundColor: fg.withAlphaComponent(a),
        ])
        let sz = str.size()
        str.draw(at: NSPoint(
            x: (bounds.width  - sz.width)  / 2,
            y: (bounds.height - sz.height) / 2
        ))
    }
}

// MARK: - Welcome Window Controller

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: WelcomeWindowController?

    private var screenCheckmark: NSImageView!
    private var screenOpenBtn:   PillButton!
    private var accessCheckmark: NSImageView!
    private var accessOpenBtn:   PillButton!

    // MARK: Public API

    static func showIfNeeded() {
        let seen    = UserDefaults.standard.bool(forKey: "welcomeShown")
        let allGood = PermissionManager.hasScreenRecordingPermission
                   && PermissionManager.hasAccessibilityPermission
        if !seen || !allGood { show() }
    }

    static func show() {
        if shared == nil { shared = WelcomeWindowController() }
        shared?.window?.center()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Init

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError() }

    private convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 650),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        w.title                = "ScreenOCR"
        w.isReleasedWhenClosed = false
        w.minSize              = w.frame.size
        w.maxSize              = w.frame.size
        self.init(window: w)
        w.delegate = self
        buildUI()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onAppActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    // MARK: Build

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment   = .centerX
        root.spacing     = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor .constraint(equalTo: content.leadingAnchor,  constant: 32),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            root.topAnchor     .constraint(equalTo: content.topAnchor,      constant: 32),
            root.bottomAnchor  .constraint(equalTo: content.bottomAnchor,   constant: -28),
        ])

        // Header
        root.addArrangedSubview(buildHeader())
        root.setCustomSpacing(28, after: root.arrangedSubviews.last!)

        // Features
        let features = buildFeatureSection()
        root.addArrangedSubview(features)
        features.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.setCustomSpacing(22, after: features)

        // Permissions
        let perms = buildPermissionsSection()
        root.addArrangedSubview(perms)
        perms.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // Spacer above button
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(spacer)
        root.setCustomSpacing(28, after: perms)

        // Get Started
        let btn = PillButton("Get Started", style: .primary, target: self, action: #selector(getStarted))
        btn.keyEquivalent = "\r"
        root.addArrangedSubview(btn)
    }

    // MARK: Header

    private func buildHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment   = .centerX
        stack.spacing     = 0

        let icon = NSImageView()
        icon.image        = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor .constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
        ])

        let title = NSTextField(labelWithString: "ScreenOCR")
        title.font      = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center

        let sub = NSTextField(labelWithString: "Capture text, colors and SVG icons\nfrom anywhere on your screen.")
        sub.font                 = NSFont.systemFont(ofSize: 14)
        sub.textColor            = .secondaryLabelColor
        sub.alignment            = .center
        sub.lineBreakMode        = .byWordWrapping
        sub.maximumNumberOfLines = 2

        stack.addArrangedSubview(icon)
        stack.setCustomSpacing(12, after: icon)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(6, after: title)
        stack.addArrangedSubview(sub)

        return stack
    }

    // MARK: Features

    private func buildFeatureSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment   = .leading
        section.spacing     = 0
        section.translatesAutoresizingMaskIntoConstraints = false

        let lbl = eyebrowLabel("WHAT IT DOES")
        section.addArrangedSubview(lbl)
        section.setCustomSpacing(10, after: lbl)

        let items: [(String, String)] = [
            ("Text OCR",     "Select any screen area — text is copied to your clipboard instantly."),
            ("Color Picker", "Hover to preview any color as a HEX code. Click to copy."),
            ("SVG Capture",  "Click any vector element in a browser to grab its SVG source."),
        ]

        for (i, (t, d)) in items.enumerated() {
            let card = featureCard(title: t, desc: d)
            section.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
            if i < items.count - 1 {
                section.setCustomSpacing(6, after: card)
            }
        }

        return section
    }

    private func featureCard(title: String, desc: String) -> NSView {
        let box = NSBox()
        box.boxType            = .custom
        box.borderColor        = NSColor.separatorColor
        box.borderWidth        = 1
        box.cornerRadius       = 8
        box.fillColor          = NSColor.controlBackgroundColor
        box.contentViewMargins = NSSize.zero
        box.translatesAutoresizingMaskIntoConstraints = false

        guard let cv = box.contentView else { return box }

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment   = .leading
        inner.spacing     = 3
        inner.edgeInsets  = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        inner.translatesAutoresizingMaskIntoConstraints = false

        let t = NSTextField(labelWithString: title)
        t.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        let d = NSTextField(labelWithString: desc)
        d.font                 = NSFont.systemFont(ofSize: 14)
        d.textColor            = .secondaryLabelColor
        d.lineBreakMode        = .byWordWrapping
        d.maximumNumberOfLines = 2

        inner.addArrangedSubview(t)
        inner.addArrangedSubview(d)

        cv.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor     .constraint(equalTo: cv.topAnchor),
            inner.bottomAnchor  .constraint(equalTo: cv.bottomAnchor),
            inner.leadingAnchor .constraint(equalTo: cv.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        ])

        return box
    }

    // MARK: Permissions

    private func buildPermissionsSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment   = .leading
        section.spacing     = 0
        section.translatesAutoresizingMaskIntoConstraints = false

        let lbl = eyebrowLabel("PERMISSIONS")
        section.addArrangedSubview(lbl)
        section.setCustomSpacing(10, after: lbl)

        let box = NSBox()
        box.boxType            = .custom
        box.borderColor        = NSColor.separatorColor
        box.borderWidth        = 1
        box.cornerRadius       = 8
        box.fillColor          = NSColor.controlBackgroundColor
        box.contentViewMargins = NSSize.zero
        box.translatesAutoresizingMaskIntoConstraints = false

        guard let cv = box.contentView else {
            section.addArrangedSubview(box)
            return section
        }

        let (sv, sChk, sBtn) = permRow(
            title:  "Screen Recording",
            detail: "Required to capture screen content",
            action: #selector(openScreenSettings)
        )
        screenCheckmark = sChk
        screenOpenBtn   = sBtn

        let sep = hairline()

        let (av, aChk, aBtn) = permRow(
            title:  "Accessibility",
            detail: "Required for global hotkey  ⌘⇧1",
            action: #selector(openAccessSettings)
        )
        accessCheckmark = aChk
        accessOpenBtn   = aBtn

        [sv, sep, av].forEach { cv.addSubview($0) }

        NSLayoutConstraint.activate([
            sv.topAnchor     .constraint(equalTo: cv.topAnchor),
            sv.leadingAnchor .constraint(equalTo: cv.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            sep.topAnchor     .constraint(equalTo: sv.bottomAnchor),
            sep.leadingAnchor .constraint(equalTo: cv.leadingAnchor, constant: 14),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
            sep.heightAnchor  .constraint(equalToConstant: 0.5),

            av.topAnchor     .constraint(equalTo: sep.bottomAnchor),
            av.leadingAnchor .constraint(equalTo: cv.leadingAnchor),
            av.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            av.bottomAnchor  .constraint(equalTo: cv.bottomAnchor),
        ])

        section.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        refreshPermissions()
        return section
    }

    private func permRow(title: String, detail: String, action: Selector) -> (NSView, NSImageView, PillButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        titleLbl.translatesAutoresizingMaskIntoConstraints = false

        let detailLbl = NSTextField(labelWithString: detail)
        detailLbl.font      = NSFont.systemFont(ofSize: 13)
        detailLbl.textColor = .secondaryLabelColor
        detailLbl.translatesAutoresizingMaskIntoConstraints = false

        // Green checkmark (shown when granted)
        let cfg  = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let img  = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                       .withSymbolConfiguration(cfg)
        let checkmark = NSImageView(image: img ?? NSImage())
        checkmark.contentTintColor = .systemGreen
        checkmark.isHidden         = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkmark.widthAnchor .constraint(equalToConstant: 22),
            checkmark.heightAnchor.constraint(equalToConstant: 22),
        ])

        let openBtn = PillButton("Open Settings", style: .secondary, target: self, action: action)
        openBtn.isHidden = false

        [titleLbl, detailLbl, checkmark, openBtn].forEach { row.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor .constraint(equalTo: row.leadingAnchor, constant: 14),
            titleLbl.topAnchor     .constraint(equalTo: row.topAnchor, constant: 11),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: openBtn.leadingAnchor, constant: -8),

            detailLbl.leadingAnchor .constraint(equalTo: titleLbl.leadingAnchor),
            detailLbl.topAnchor     .constraint(equalTo: titleLbl.bottomAnchor, constant: 3),
            detailLbl.trailingAnchor.constraint(lessThanOrEqualTo: openBtn.leadingAnchor, constant: -8),

            checkmark.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            checkmark.centerYAnchor .constraint(equalTo: row.centerYAnchor),

            openBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            openBtn.centerYAnchor .constraint(equalTo: row.centerYAnchor),
        ])

        return (row, checkmark, openBtn)
    }

    // MARK: Helpers

    private func eyebrowLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font      = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        f.textColor = .tertiaryLabelColor
        return f
    }

    private func hairline() -> NSBox {
        let b = NSBox()
        b.boxType            = .custom
        b.borderWidth        = 0
        b.cornerRadius       = 0
        b.fillColor          = NSColor.separatorColor
        b.contentViewMargins = NSSize.zero
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    // MARK: Permissions Refresh

    @objc private func onAppActive() {
        guard isWindowLoaded, window?.isVisible == true else { return }
        refreshPermissions()
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshPermissions() }

    private func refreshPermissions() {
        apply(PermissionManager.hasScreenRecordingPermission, checkmark: screenCheckmark, btn: screenOpenBtn)
        apply(PermissionManager.hasAccessibilityPermission,  checkmark: accessCheckmark, btn: accessOpenBtn)
    }

    private func apply(_ granted: Bool, checkmark: NSImageView?, btn: PillButton?) {
        checkmark?.isHidden = !granted
        btn?.isHidden       = granted
    }

    @objc private func openScreenSettings() {
        // Register via ScreenCaptureKit so app appears in "Screen & System Audio Recording" list
        PermissionManager.registerWithScreenCaptureKit()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func openAccessSettings() {
        // Always call to register app in TCC database
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Window Actions

    @objc private func getStarted() {
        UserDefaults.standard.set(true, forKey: "welcomeShown")
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "welcomeShown")
    }
}
