import Cocoa
import Vision

// MARK: - Selection View

final class SelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var isSVGMode = false
    var backgroundImage: CGImage?

    private var startPoint: NSPoint = .zero
    private var selectionRect: NSRect = .zero
    private var isSelecting = false
    private var isDragging = false
    private var isMoving = false
    private var lastDragPoint: NSPoint = .zero
    private var dashPhase: CGFloat = 0
    private var timer: Timer?
    private var hoveredBox: CGRect? = nil

    var screenWordBoxes: [CGRect] = []     // word-level boxes (⌘⇧1 fast)
    var screenSVGBoxes: [CGRect] = []      // SVG element boxes (⌘⇧2)

    override var acceptsFirstResponder: Bool { true }

    private var activeBoxes: [CGRect] {
        isSVGMode ? screenSVGBoxes : screenWordBoxes
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.dashPhase -= 2.0
                self?.needsDisplay = true
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Hover

    override func mouseMoved(with event: NSEvent) {
        guard !isSelecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoveredBox = activeBoxes.first(where: { $0.contains(point) })
        needsDisplay = true
    }

    // MARK: Selection

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        isSelecting = true
        isDragging = false
    }

    private var spaceDown: Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(49))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let current = convert(event.locationInWindow, from: nil)

        if !isDragging {
            let dist = hypot(current.x - startPoint.x, current.y - startPoint.y)
            if dist > 3 {
                isDragging = true
                hoveredBox = nil
            } else {
                return
            }
        }

        let spacePressed = spaceDown

        if spacePressed && !isMoving {
            isMoving = true
            lastDragPoint = current
        } else if !spacePressed && isMoving {
            isMoving = false
        }

        if isMoving {
            let dx = current.x - lastDragPoint.x
            let dy = current.y - lastDragPoint.y
            selectionRect.origin.x += dx
            selectionRect.origin.y += dy
            startPoint.x += dx
            startPoint.y += dy
            lastDragPoint = current
        } else {
            selectionRect = NSRect(
                x: min(startPoint.x, current.x),
                y: min(startPoint.y, current.y),
                width: abs(current.x - startPoint.x),
                height: abs(current.y - startPoint.y)
            )
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false

        // Single click (no drag) — use hovered box
        if !isDragging {
            let clickPoint = convert(event.locationInWindow, from: nil)
            guard let box = activeBoxes.first(where: { $0.contains(clickPoint) }) else {
                onCancel?()
                return
            }
            completeWith(viewRect: box)
            return
        }

        // Inflate thin selections so they intersect word boxes
        var inflated = selectionRect
        if inflated.height < 10 {
            inflated = inflated.insetBy(dx: 0, dy: -10)
        }
        if inflated.width < 10 {
            inflated = inflated.insetBy(dx: -10, dy: 0)
        }

        var finalRect = inflated
        if !isSVGMode {
            for box in screenWordBoxes where inflated.intersects(box) {
                finalRect = finalRect.union(box)
            }
        }

        // Nothing captured — cancel
        guard finalRect.width > 2, finalRect.height > 2 else {
            onCancel?()
            return
        }

        completeWith(viewRect: finalRect)
    }

    private func completeWith(viewRect: NSRect) {
        let windowRect = convert(viewRect, to: nil)
        let screenRect = window!.convertToScreen(windowRect)

        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: mainDisplayHeight - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )

        onComplete?(cgRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw frozen screenshot as background
        if let bg = backgroundImage {
            let nsImage = NSImage(cgImage: bg, size: bounds.size)
            nsImage.draw(in: bounds)
        }

        let hex = UserDefaults.standard.string(forKey: "highlightColorHex") ?? "FFD60A"
        let highlightColor = NSColor(hex: hex)
        let dashPattern: [CGFloat] = [4.0, 4.0]
        let cornerRadius: CGFloat = 4

        // Hover highlight (before dragging)
        if !isSelecting || !isDragging, let box = hoveredBox {
            highlightColor.setStroke()
            let path = NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius)
            path.setLineDash(dashPattern, count: 2, phase: dashPhase)
            path.lineWidth = 2.5
            path.stroke()
            highlightColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        // Selection highlight & border
        if isDragging && selectionRect.width > 0 && selectionRect.height > 0 {
            context.setFillColor(NSColor(white: 0.5, alpha: 0.12).cgColor)
            context.fill(selectionRect)

            let outerPath = NSBezierPath(rect: selectionRect.insetBy(dx: -1, dy: -1))
            NSColor.black.withAlphaComponent(0.35).setStroke()
            outerPath.lineWidth = 1.0
            outerPath.stroke()

            let innerPath = NSBezierPath(rect: selectionRect)
            NSColor.white.withAlphaComponent(0.8).setStroke()
            innerPath.lineWidth = 1.0
            innerPath.stroke()

            drawSizeLabel(context: context)

            // Merge intersecting boxes on same line, then draw
            let hitBoxes = activeBoxes.filter { selectionRect.intersects($0) }
            let merged = mergeBoxesByLine(hitBoxes)

            highlightColor.setStroke()
            for box in merged {
                let path = NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius)
                path.setLineDash(dashPattern, count: 2, phase: dashPhase)
                path.lineWidth = 2.5
                path.stroke()
                highlightColor.withAlphaComponent(0.15).setFill()
                NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }
        }
    }

    /// Groups boxes that share the same line (similar midY) and merges them into continuous rects.
    private func mergeBoxesByLine(_ boxes: [CGRect]) -> [CGRect] {
        guard !boxes.isEmpty else { return [] }

        // Group by approximate Y center (tolerance = half the median box height)
        let sorted = boxes.sorted { $0.midY < $1.midY }
        let medianH = boxes.map(\.height).sorted()[boxes.count / 2]
        let tolerance = medianH * 0.5

        var lines: [[CGRect]] = []
        var currentLine: [CGRect] = [sorted[0]]

        for i in 1..<sorted.count {
            if abs(sorted[i].midY - currentLine[0].midY) <= tolerance {
                currentLine.append(sorted[i])
            } else {
                lines.append(currentLine)
                currentLine = [sorted[i]]
            }
        }
        lines.append(currentLine)

        // Within each line, sort by X and merge overlapping/adjacent boxes
        var result: [CGRect] = []
        for line in lines {
            let byX = line.sorted { $0.minX < $1.minX }
            var merged = byX[0]
            for i in 1..<byX.count {
                let gap = byX[i].minX - merged.maxX
                if gap < medianH { // close enough to merge
                    merged = merged.union(byX[i])
                } else {
                    result.append(merged)
                    merged = byX[i]
                }
            }
            result.append(merged)
        }
        return result
    }

    private func drawSizeLabel(context: CGContext) {
        let w = Int(selectionRect.width)
        let h = Int(selectionRect.height)
        let label = "\(w) × \(h)" as NSString

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        let padding: CGFloat = 6
        let bgRect = CGRect(
            x: selectionRect.midX - (size.width + padding * 2) / 2,
            y: selectionRect.minY - size.height - padding * 2 - 4,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )

        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        label.draw(
            at: NSPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding),
            withAttributes: attrs
        )
    }
}

// MARK: - Key-accepting borderless window

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay Window

final class OverlayWindow {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect) -> Void)?
    private var cancellation: (() -> Void)?

    // MARK: Fast mode — .fast recognition, word boxes

    func showFast(screenImages: [(displayID: CGDirectDisplayID, image: CGImage)], onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        showOverlay(isSVG: false, screenImages: screenImages, onComplete: onComplete, onCancel: onCancel, immediate: true)
        preScanWordBoxes(level: .fast, screenImages: screenImages)
    }

    // MARK: Accurate mode — .accurate recognition, word boxes

    func showAccurate(screenImages: [(displayID: CGDirectDisplayID, image: CGImage)], onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        showOverlay(isSVG: false, screenImages: screenImages, onComplete: onComplete, onCancel: onCancel, immediate: true)
        preScanWordBoxes(level: .accurate, screenImages: screenImages)
    }

    func preScanWordBoxes(level: VNRequestTextRecognitionLevel, screenImages: [(displayID: CGDirectDisplayID, image: CGImage)]) {
        let imageByDisplay = Dictionary(uniqueKeysWithValues: screenImages.map { ($0.displayID, $0.image) })

        for window in windows {
            guard let view = window.contentView as? SelectionView,
                  let screen = window.screen,
                  let displayID = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID,
                  let image = imageByDisplay[displayID] else { continue }

            let request = VNRecognizeTextRequest { [weak view] request, _ in
                guard let results = request.results as? [VNRecognizedTextObservation], !results.isEmpty else { return }

                var wordBoxes: [CGRect] = []
                for obs in results {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let str = candidate.string
                    let words = str.split(separator: " ", omittingEmptySubsequences: true)
                    var searchStart = str.startIndex
                    for word in words {
                        guard let wordRange = str.range(of: word, range: searchStart..<str.endIndex) else { continue }
                        searchStart = wordRange.upperBound
                        if let bb = try? candidate.boundingBox(for: wordRange) {
                            let w = bb.boundingBox.width * screen.frame.width
                            let h = bb.boundingBox.height * screen.frame.height
                            let x = bb.boundingBox.minX * screen.frame.width
                            let y = bb.boundingBox.minY * screen.frame.height
                            wordBoxes.append(CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -6, dy: -4))
                        }
                    }
                }

                DispatchQueue.main.async {
                    view?.screenWordBoxes = wordBoxes
                    view?.needsDisplay = true
                }
            }
            request.recognitionLevel = level
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    // MARK: SVG mode

    func showForSVG(screenImages: [(displayID: CGDirectDisplayID, image: CGImage)], onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        showOverlay(isSVG: true, screenImages: screenImages, onComplete: onComplete, onCancel: onCancel, immediate: true)
    }

    /// Update SVG bounding boxes on all overlay views. cgBoxes are in CG coordinates (top-left origin).
    func setSVGBoxes(_ cgBoxes: [CGRect]) {
        let mainH = CGDisplayBounds(CGMainDisplayID()).height
        for window in windows {
            guard let view = window.contentView as? SelectionView else { continue }
            let screen = window.screen ?? NSScreen.main!
            view.screenSVGBoxes = cgBoxes.map { cg in
                CGRect(
                    x: cg.origin.x - screen.frame.origin.x,
                    y: mainH - cg.origin.y - cg.height - screen.frame.origin.y,
                    width: cg.width,
                    height: cg.height
                ).insetBy(dx: -6, dy: -4)
            }
            view.needsDisplay = true
        }
    }

    func switchToOCRMode() {
        for window in windows {
            if let view = window.contentView as? SelectionView {
                view.isSVGMode = false
                view.needsDisplay = true
            }
        }
    }

    func switchToSVGMode() {
        for window in windows {
            if let view = window.contentView as? SelectionView {
                view.isSVGMode = true
                view.needsDisplay = true
            }
        }
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        NSCursor.arrow.set()
        windows.removeAll()
    }

    // MARK: Private

    private func showOverlay(isSVG: Bool, screenImages: [(displayID: CGDirectDisplayID, image: CGImage)], onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void, immediate: Bool) {
        NSCursor.crosshair.set()
        self.completion = onComplete
        self.cancellation = onCancel

        let imageByDisplay = Dictionary(uniqueKeysWithValues: screenImages.map { ($0.displayID, $0.image) })

        for screen in NSScreen.screens {
            let window = KeyWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(Int(CGShieldingWindowLevel()))
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false

            let view = SelectionView(frame: screen.frame)
            view.isSVGMode = isSVG

            // Set frozen screenshot as background
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                view.backgroundImage = imageByDisplay[displayID]
            }

            view.onComplete = { [weak self] cgRect in
                guard let self = self else { return }
                self.dismiss()
                if immediate {
                    self.completion?(cgRect)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.completion?(cgRect)
                    }
                }
            }
            view.onCancel = { [weak self] in
                self?.dismiss()
                self?.cancellation?()
            }

            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)

            view.discardCursorRects()
            view.resetCursorRects()
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeFirstResponder(windows.first?.contentView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSCursor.crosshair.set()
        }
    }
}
