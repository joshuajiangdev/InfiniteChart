#if canImport(UIKit)
import UIKit

/// The native color type used by chart configuration and data providers.
public typealias ChartColor = UIColor
/// The native font type used by chart axis labels.
public typealias ChartFont = UIFont

typealias ChartPanGestureRecognizer = UIPanGestureRecognizer
typealias ChartPinchGestureRecognizer = UIPinchGestureRecognizer

/// Bridges native view layout to the shared chart implementation.
open class ChartPlatformView: UIView {
    open func layoutChartSubviews() {}

    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutChartSubviews()
    }

    func configureChartAppearance(background: ChartColor) {
        backgroundColor = background
        isOpaque = false
        clipsToBounds = true
    }

    func requestChartLayout() { setNeedsLayout() }
    func requestChartDisplay() { setNeedsDisplay() }
}

@MainActor
func currentChartGraphicsContext() -> CGContext? {
    UIGraphicsGetCurrentContext()
}

extension ChartPinchGestureRecognizer {
    var chartScale: CGFloat {
        get { scale }
        set { scale = newValue }
    }
}
#elseif canImport(AppKit)
import AppKit

/// The native color type used by chart configuration and data providers.
public typealias ChartColor = NSColor
/// The native font type used by chart axis labels.
public typealias ChartFont = NSFont

typealias ChartPanGestureRecognizer = NSPanGestureRecognizer
typealias ChartPinchGestureRecognizer = NSMagnificationGestureRecognizer

/// An AppKit view with the same top-left origin as the chart's coordinates.
open class ChartPlatformView: NSView {
    open override var isFlipped: Bool { true }

    open func layoutChartSubviews() {}

    open override func layout() {
        super.layout()
        layoutChartSubviews()
    }

    func configureChartAppearance(background: ChartColor) {
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
        layer?.masksToBounds = true
    }

    func requestChartLayout() { needsLayout = true }
    func requestChartDisplay() { needsDisplay = true }

    open override func scrollWheel(with event: NSEvent) {
        guard let pannable = self as? any Pannable else {
            super.scrollWheel(with: event)
            return
        }
        // Trackpads report points; traditional wheels report lines.
        let pointsPerUnit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        pannable.pan(by: CGPoint(
            x: event.scrollingDeltaX * pointsPerUnit,
            y: event.scrollingDeltaY * pointsPerUnit
        ))
    }
}

@MainActor
func currentChartGraphicsContext() -> CGContext? {
    NSGraphicsContext.current?.cgContext
}

extension ChartPinchGestureRecognizer {
    var chartScale: CGFloat {
        get { 1 + magnification }
        set { magnification = newValue - 1 }
    }
}
#endif

extension ChartPlatformView {
    func installChartGestures(panAction: Selector, pinchAction: Selector) {
        let pan = ChartPanGestureRecognizer(target: self, action: panAction)
        #if canImport(UIKit)
        pan.maximumNumberOfTouches = 1
        #endif
        addGestureRecognizer(pan)
        addGestureRecognizer(ChartPinchGestureRecognizer(target: self, action: pinchAction))
    }
}
