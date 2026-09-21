import CoreGraphics
import Combine

/// Maintains chart coordinates using Core Graphics affine transforms.
/// Scales must be positive and finite; invalid updates leave the transform unchanged.
public final class AffineTransformerProvider: TransformerProviding {
    private(set) var chartWidth: CGFloat
    private(set) var chartHeight: CGFloat
    private(set) var hasValidDataRanges = false

    @Published private(set) var transformer: AffineTransformer
    lazy var transformerStream: AnyPublisher<AffineTransformer, Never> = $transformer
        .filter { [weak self] _ in self?.hasValidDataRanges == true }
        .eraseToAnyPublisher()

    public init(size: CGSize, dataRanges: DataRanges) {
        chartWidth = size.width.isFinite && size.width > 0 ? size.width : 1
        chartHeight = size.height.isFinite && size.height > 0 ? size.height : 1
        // Keep an invertible placeholder until a provider supplies valid ranges.
        transformer = AffineTransformer(valueToPixel: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0))!
        prepareMatrixValuePx(dataRanges: dataRanges)
    }

    /// A snapshot derived from the supplied transform and current plot dimensions.
    func viewport(for transformer: AffineTransformer) -> ChartViewport? {
        guard hasValidDataRanges, chartWidth > 0, chartHeight > 0 else { return nil }
        let topLeft = transformer.valueForTouchPoint(.zero)
        let bottomRight = transformer.valueForTouchPoint(CGPoint(x: chartWidth, y: chartHeight))
        guard topLeft.x.isFinite, topLeft.y.isFinite, bottomRight.x.isFinite, bottomRight.y.isFinite,
              topLeft.x < bottomRight.x, bottomRight.y < topLeft.y else { return nil }
        return ChartViewport(visibleXRange: topLeft.x...bottomRight.x,
                             visibleYRange: bottomRight.y...topLeft.y,
                             plotSize: CGSize(width: chartWidth, height: chartHeight))
    }

    /// Resize the plot without resetting its visible data ranges.
    func setChartDimens(width: CGFloat, height: CGFloat) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        let resized = transformer.valueToPixelTransform.concatenating(
            CGAffineTransform(scaleX: width / chartWidth, y: height / chartHeight)
        )
        guard let next = AffineTransformer(valueToPixel: resized) else { return }
        chartWidth = width
        chartHeight = height
        publish(next)
    }

    func prepareMatrixValuePx(dataRanges: DataRanges) {
        guard dataRanges.chartXMin.isFinite, dataRanges.chartYMin.isFinite,
              dataRanges.deltaX.isFinite, dataRanges.deltaY.isFinite,
              dataRanges.deltaX > 0, dataRanges.deltaY > 0,
              (dataRanges.chartXMin + dataRanges.deltaX).isFinite,
              (dataRanges.chartYMin + dataRanges.deltaY).isFinite,
              dataRanges.chartXMin + dataRanges.deltaX > dataRanges.chartXMin,
              dataRanges.chartYMin + dataRanges.deltaY > dataRanges.chartYMin else { return }
        let scaleX = chartWidth / dataRanges.deltaX
        let scaleY = chartHeight / dataRanges.deltaY
        let transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: -scaleY,
                                          tx: -dataRanges.chartXMin * scaleX,
                                          ty: chartHeight + dataRanges.chartYMin * scaleY)
        guard let next = AffineTransformer(valueToPixel: transform) else { return }
        let wasValid = hasValidDataRanges
        hasValidDataRanges = true
        if !wasValid || next != transformer {
            transformer = next
        }
    }

    public func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        guard hasValidDataRanges, scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              x.isFinite, y.isFinite else { return }
        // Compose in pixel space so the gesture anchor remains fixed.
        let zoom = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY,
                                     tx: (1 - scaleX) * x, ty: (1 - scaleY) * y)
        update(transformer.valueToPixelTransform.concatenating(zoom))
    }

    public func translate(delta: CGPoint) {
        guard hasValidDataRanges, delta.x.isFinite, delta.y.isFinite else { return }
        update(transformer.valueToPixelTransform.concatenating(
            CGAffineTransform(translationX: delta.x, y: delta.y)
        ))
    }

    private func update(_ transform: CGAffineTransform) {
        guard let next = AffineTransformer(valueToPixel: transform), viewport(for: next) != nil else { return }
        publish(next)
    }

    private func publish(_ next: AffineTransformer) {
        guard next != transformer else { return }
        transformer = next
    }
}

@available(*, deprecated, renamed: "AffineTransformerProvider")
public typealias AccelerateTransformerProvider = AffineTransformerProvider
