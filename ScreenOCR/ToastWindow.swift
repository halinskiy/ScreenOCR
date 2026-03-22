import Cocoa

final class ToastWindow: NSWindow {
    private static var current: ToastWindow?

    static func show(_ message: String) {
        current?.orderOut(nil)

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (message as NSString).size(withAttributes: attrs)

        let hPad: CGFloat = 16
        let vPad: CGFloat = 8
        let width = textSize.width + hPad * 2
        let height = textSize.height + vPad * 2

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - width / 2
        let y = screen.frame.midY - height / 2 - screen.frame.height * 0.2
        let frame = NSRect(x: x, y: y, width: width, height: height)

        let toast = ToastWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        toast.level = .init(Int(CGShieldingWindowLevel()) + 1)
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = false
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .transient]
        toast.isReleasedWhenClosed = false

        let view = ToastView(frame: NSRect(x: 0, y: 0, width: width, height: height), message: message, attrs: attrs)
        toast.contentView = view

        toast.alphaValue = 0
        toast.orderFrontRegardless()

        current = toast

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.orderOut(nil)
                if current === toast { current = nil }
            })
        }
    }
}

private final class ToastView: NSView {
    let message: String
    let attrs: [NSAttributedString.Key: Any]

    init(frame: NSRect, message: String, attrs: [NSAttributedString.Key: Any]) {
        self.message = message
        self.attrs = attrs
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        path.fill()

        let textSize = (message as NSString).size(withAttributes: attrs)
        let x = (bounds.width - textSize.width) / 2
        let y = (bounds.height - textSize.height) / 2
        (message as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}
