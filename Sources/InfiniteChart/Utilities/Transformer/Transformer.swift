import CoreGraphics

public struct DoublePrecisionPoint: Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public protocol Transformer: Equatable {
    func valueForTouchPoint(_ point: CGPoint) -> DoublePrecisionPoint
    func pixelForValue(_ point: DoublePrecisionPoint) -> CGPoint
}

/// An immutable pair of forward and inverse chart coordinate transforms.
public struct AffineTransformer: Transformer {
    let valueToPixelTransform: CGAffineTransform
    let pixelToValueTransform: CGAffineTransform

    init?(valueToPixel transform: CGAffineTransform) {
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard transform.isFinite, determinant.isFinite, determinant != 0 else { return nil }
        let inverse = transform.inverted()
        guard inverse.isFinite else { return nil }
        valueToPixelTransform = transform
        pixelToValueTransform = inverse
    }

    public func valueForTouchPoint(_ point: CGPoint) -> DoublePrecisionPoint {
        let value = point.applying(pixelToValueTransform)
        return DoublePrecisionPoint(x: Double(value.x), y: Double(value.y))
    }

    public func pixelForValue(_ point: DoublePrecisionPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y).applying(valueToPixelTransform)
    }
}

extension CGAffineTransform {
    var isFinite: Bool {
        a.isFinite && b.isFinite && c.isFinite && d.isFinite && tx.isFinite && ty.isFinite
    }
}

@available(*, deprecated, renamed: "AffineTransformer")
public typealias AccelerateTransformer = AffineTransformer
