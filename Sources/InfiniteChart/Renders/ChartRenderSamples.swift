import CoreGraphics

/// Keeps iteration and bar spacing consistent across the built-in renderers.
enum ChartRenderSamples {
    static func xValues(
        dataProvider: any ChartDataProviderBase,
        transformerProvider: AccelerateTransformerProvider
    ) -> AnySequence<Double> {
        let transformer = transformerProvider.transformer
        let left = transformer.valueForTouchPoint(.zero).x
        let right = transformer.valueForTouchPoint(CGPoint(x: transformerProvider.chartWidth, y: 0)).x
        guard left.isFinite, right.isFinite else { return AnySequence([]) }

        if let indexed = dataProvider as? any IndexedChartDataProvider {
            // Include a neighboring sample on each side so clipped bars and line
            // segments remain visible when their centers fall outside the plot.
            let lowerBound = min(left, right)
            let upperBound = max(left, right)
            let previous = dataProvider.getClosestXValue(to: lowerBound, seekBelow: true, offset: 0)
            let next = dataProvider.getClosestXValue(to: upperBound, seekBelow: false, offset: 0)
            let start = previous.flatMap { $0.isFinite ? min(lowerBound, $0) : nil } ?? lowerBound
            let end = next.flatMap { $0.isFinite ? max(upperBound, $0) : nil } ?? upperBound
            return AnySequence(indexed.getXValues(in: start...end))
        }

        // Preserve the original behavior for existing data providers.
        let lowerBound = min(left, right).rounded(.up)
        let upperBound = max(left, right).rounded(.down)
        let start = dataProvider.getClosestXValue(to: lowerBound, seekBelow: true, offset: 1) ?? lowerBound
        let end = dataProvider.getClosestXValue(to: upperBound, seekBelow: false, offset: 1) ?? upperBound
        guard start.isFinite, end.isFinite, start <= end else { return AnySequence([]) }
        return AnySequence(stride(from: start, through: end, by: 60_000))
    }

    static func barWidth(
        dataProvider: any ChartDataProviderBase,
        transformerProvider: AccelerateTransformerProvider,
        legacyWidth: CGFloat
    ) -> CGFloat {
        guard let indexed = dataProvider as? any IndexedChartDataProvider,
              indexed.nominalXStep.isFinite, indexed.nominalXStep > 0 else {
            return legacyWidth
        }
        let transformer = transformerProvider.transformer
        let anchor = transformer.valueForTouchPoint(.zero).x
        let start = transformer.pixelForValue(DoublePrecisionPoint(x: anchor, y: 0)).x
        let end = transformer.pixelForValue(DoublePrecisionPoint(x: anchor + indexed.nominalXStep, y: 0)).x
        let spacing = abs(end - start)
        guard spacing.isFinite else { return legacyWidth }
        // A missing interval must remain a gap, rather than widening its neighbors.
        return min(24, max(1, spacing * 0.8))
    }
}
