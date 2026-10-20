import AppKit
import ClawCopyCore

/// Watches left-mouse events system-wide (passively; events are never modified or blocked)
/// and reports when a gesture that likely selected text has finished.
@MainActor
final class MouseMonitor {
    var onSelectionGesture: (() -> Void)?

    private var detector = SelectionGestureDetector()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            // Extract plain values here; hop to the main actor to update state.
            let type = event.type
            let location = Point(x: Double(event.locationInWindow.x), y: Double(event.locationInWindow.y))
            let clickCount = event.clickCount
            let shift = event.modifierFlags.contains(.shift)
            Task { @MainActor [weak self] in
                self?.handle(type: type, location: location, clickCount: clickCount, shift: shift)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(type: NSEvent.EventType, location: Point, clickCount: Int, shift: Bool) {
        switch type {
        case .leftMouseDown:
            detector.mouseDown(at: location, shift: shift)
        case .leftMouseDragged:
            detector.mouseDragged(to: location)
        case .leftMouseUp:
            if detector.mouseUp(at: location, clickCount: clickCount) {
                onSelectionGesture?()
            }
        default:
            break
        }
    }
}
