import AppKit

/// Transparent top-level panels used while this Mac is controlling a peer.
///
/// CGEvent taps can fall back to a session-level tap when macOS refuses HID-level
/// capture. In that mode local delivery can be suppressed, but the visual cursor
/// may still move briefly. These panels keep the local cursor invisible and eat
/// accidental local mouse interaction until ownership returns to this Mac.
final class CursorShieldController {
    private var panels: [CursorShieldPanel] = []
    private var panelFrames: [CGRect] = []
    private let invisibleCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)

    func show() {
        performOnMain { [weak self] in
            self?.showOnMain()
        }
    }

    func hide() {
        performOnMain { [weak self] in
            self?.hideOnMain()
        }
    }

    private func showOnMain() {
        let frames = NSScreen.screens.map(\.frame)
        if panels.isEmpty || frames != panelFrames {
            hideOnMain()
            panelFrames = frames
            panels = frames.map { frame in
                let panel = CursorShieldPanel(
                    contentRect: frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.acceptsMouseMovedEvents = true
                panel.ignoresMouseEvents = false
                panel.contentView = CursorShieldView(frame: CGRect(origin: .zero, size: frame.size), cursor: invisibleCursor)
                return panel
            }
        }

        for panel in panels {
            panel.orderFrontRegardless()
        }
        invisibleCursor.set()
    }

    private func hideOnMain() {
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        panelFrames.removeAll()
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

private final class CursorShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CursorShieldView: NSView {
    private let cursor: NSCursor

    init(frame: CGRect, cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        cursor.set()
    }

    override func rightMouseDragged(with event: NSEvent) {
        cursor.set()
    }

    override func otherMouseDragged(with event: NSEvent) {
        cursor.set()
    }
}
