import Foundation

/// A screen location, kept independent of CoreGraphics so the core stays portable and testable.
public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: Point) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Decides whether a left-mouse interaction most likely produced a text selection.
///
/// A selection gesture is one of:
/// - a click-and-drag that moved at least `dragThreshold` points,
/// - a double or triple click (word / line selection),
/// - a shift-click (extends an existing selection).
public struct SelectionGestureDetector: Sendable {
    public var dragThreshold: Double

    private var downLocation: Point?
    private var maxDragDistance: Double = 0
    private var shiftHeld = false

    public init(dragThreshold: Double = 4) {
        self.dragThreshold = dragThreshold
    }

    public mutating func mouseDown(at location: Point, shift: Bool) {
        downLocation = location
        maxDragDistance = 0
        shiftHeld = shift
    }

    public mutating func mouseDragged(to location: Point) {
        guard let downLocation else { return }
        maxDragDistance = max(maxDragDistance, downLocation.distance(to: location))
    }

    /// Returns `true` when the completed gesture looks like a text selection.
    public mutating func mouseUp(at location: Point, clickCount: Int) -> Bool {
        defer { reset() }
        guard let downLocation else { return false }

        let dragDistance = max(maxDragDistance, downLocation.distance(to: location))
        if dragDistance >= dragThreshold { return true }
        if clickCount >= 2 { return true }
        if shiftHeld && clickCount == 1 { return true }
        return false
    }

    private mutating func reset() {
        downLocation = nil
        maxDragDistance = 0
        shiftHeld = false
    }
}
