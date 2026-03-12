import AppKit
import MetalKit

@MainActor
protocol ViewportInputHandling: AnyObject {
    func viewportDidOrbit(delta: CGSize)
    func viewportDidPan(delta: CGSize)
    func viewportDidZoom(delta: CGFloat)
    func viewportDidShiftFrame(x: Int, y: Int, z: Int)
    func viewportDidHover(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func viewportModifiersDidChange(_ modifiers: NSEvent.ModifierFlags)
    func viewportDidPrimaryDown(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func viewportDidPrimaryClick(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func viewportDidPrimaryDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func viewportDidPrimaryUp(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func viewportDidCancelAction()
}

final class ViewportInputView: MTKView {
    weak var inputHandler: ViewportInputHandling?
    private var trackingAreaRef: NSTrackingArea?
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var isCommandOrbiting = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: activeCursor)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastModifierFlags = event.modifierFlags
        requestCursorUpdate()
        guard !event.modifierFlags.contains(.command) else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        inputHandler?.viewportDidPrimaryDown(at: point, modifiers: event.modifierFlags)
        inputHandler?.viewportDidPrimaryClick(at: point, modifiers: event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        lastModifierFlags = event.modifierFlags
        guard event.modifierFlags.contains(.command) else {
            isCommandOrbiting = false
            requestCursorUpdate()
            let point = convert(event.locationInWindow, from: nil)
            inputHandler?.viewportDidHover(at: point, modifiers: event.modifierFlags)
            inputHandler?.viewportDidPrimaryDrag(at: point, modifiers: event.modifierFlags)
            return
        }
        if !isCommandOrbiting {
            isCommandOrbiting = true
            requestCursorUpdate()
        }
        inputHandler?.viewportDidOrbit(
            delta: CGSize(width: event.deltaX, height: event.deltaY)
        )
    }

    override func mouseMoved(with event: NSEvent) {
        lastModifierFlags = event.modifierFlags
        requestCursorUpdate()
        inputHandler?.viewportDidHover(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        lastModifierFlags = event.modifierFlags
        if isCommandOrbiting {
            isCommandOrbiting = false
            requestCursorUpdate()
        }
        inputHandler?.viewportDidPrimaryUp(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .changed || event.momentumPhase == .changed {
            if event.modifierFlags.contains(.option) {
                inputHandler?.viewportDidZoom(delta: event.scrollingDeltaY)
            } else {
                inputHandler?.viewportDidPan(
                    delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                )
            }
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        inputHandler?.viewportDidZoom(delta: event.magnification * -120)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            inputHandler?.viewportDidCancelAction()
            return
        }

        if event.modifierFlags.contains(.shift) {
            switch event.keyCode {
            case 123:
                inputHandler?.viewportDidShiftFrame(x: -1, y: 0, z: 0)
                return
            case 124:
                inputHandler?.viewportDidShiftFrame(x: 1, y: 0, z: 0)
                return
            case 125:
                if event.modifierFlags.contains(.command) {
                    inputHandler?.viewportDidShiftFrame(x: 0, y: -1, z: 0)
                } else {
                    inputHandler?.viewportDidShiftFrame(x: 0, y: 0, z: -1)
                }
                return
            case 126:
                if event.modifierFlags.contains(.command) {
                    inputHandler?.viewportDidShiftFrame(x: 0, y: 1, z: 0)
                } else {
                    inputHandler?.viewportDidShiftFrame(x: 0, y: 0, z: 1)
                }
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        lastModifierFlags = event.modifierFlags
        if !event.modifierFlags.contains(.command), isCommandOrbiting {
            isCommandOrbiting = false
        }
        requestCursorUpdate()
        inputHandler?.viewportModifiersDidChange(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    private var activeCursor: NSCursor {
        if isCommandOrbiting {
            return .closedHand
        }
        if lastModifierFlags.contains(.command) {
            return .openHand
        }
        return .arrow
    }

    private func requestCursorUpdate() {
        window?.invalidateCursorRects(for: self)
    }
}
