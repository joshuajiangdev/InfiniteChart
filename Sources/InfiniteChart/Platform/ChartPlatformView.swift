#if canImport(UIKit)
import UIKit

/// The native view superclass used by the chart's platform adapter.
public typealias ChartNativeView = UIView
/// The native color type used by chart configuration and data providers.
public typealias ChartColor = UIColor
/// The native font type used by chart axis labels.
public typealias ChartFont = UIFont

typealias ChartPanGestureRecognizer = UIPanGestureRecognizer
typealias ChartPinchGestureRecognizer = UIPinchGestureRecognizer
#elseif canImport(AppKit)
import AppKit

/// The native view superclass used by the chart's platform adapter.
public typealias ChartNativeView = NSView
/// The native color type used by chart configuration and data providers.
public typealias ChartColor = NSColor
/// The native font type used by chart axis labels.
public typealias ChartFont = NSFont

typealias ChartPanGestureRecognizer = NSPanGestureRecognizer
typealias ChartPinchGestureRecognizer = NSMagnificationGestureRecognizer
#endif

/// Bridges native view behavior to the shared chart implementation.
open class ChartPlatformView: ChartNativeView {
    open func layoutChartSubviews() {}

    #if canImport(UIKit)
    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutChartSubviews()
    }
    #elseif canImport(AppKit)
    // Match the chart's top-left coordinate origin on macOS.
    open override var isFlipped: Bool { true }

    open override func layout() {
        super.layout()
        layoutChartSubviews()
    }
    #endif

    func configureChartAppearance(background: ChartColor) {
        #if canImport(UIKit)
        backgroundColor = background
        isOpaque = false
        clipsToBounds = true
        #elseif canImport(AppKit)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
        layer?.masksToBounds = true
        #endif
    }

    func requestChartLayout() {
        #if canImport(UIKit)
        setNeedsLayout()
        #elseif canImport(AppKit)
        needsLayout = true
        #endif
    }

    func requestChartDisplay() {
        #if canImport(UIKit)
        setNeedsDisplay()
        #elseif canImport(AppKit)
        needsDisplay = true
        #endif
    }

    func installChartGestures(panAction: Selector, pinchAction: Selector) {
        let pan = ChartPanGestureRecognizer(target: self, action: panAction)
        #if canImport(UIKit)
        pan.maximumNumberOfTouches = 1
        #endif
        addGestureRecognizer(pan)
        addGestureRecognizer(ChartPinchGestureRecognizer(target: self, action: pinchAction))
    }

    #if canImport(AppKit) && !canImport(UIKit)
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
    #endif
}

@MainActor
func currentChartGraphicsContext() -> CGContext? {
    #if canImport(UIKit)
    UIGraphicsGetCurrentContext()
    #elseif canImport(AppKit)
    NSGraphicsContext.current?.cgContext
    #endif
}

extension ChartPinchGestureRecognizer {
    var chartScale: CGFloat {
        get {
            #if canImport(UIKit)
            scale
            #elseif canImport(AppKit)
            1 + magnification
            #endif
        }
        set {
            #if canImport(UIKit)
            scale = newValue
            #elseif canImport(AppKit)
            magnification = newValue - 1
            #endif
        }
    }
}
