import CoreGraphics

final class TechnicalIndicatorRender {
    let dataProvider: any ChartDataProviderBase

    /// Creates a renderer that reads the provider's technical indicator series.
    init(dataProvider: any ChartDataProviderBase) {
        self.dataProvider = dataProvider
    }

    /// Draws each indicator in its supplied point order with a two-point colored line.
    ///
    /// Nonfinite transformed coordinates break the path. Traverses each complete
    /// series and restores the graphics state after each indicator; the caller
    /// controls clipping to the plot.
    ///
    /// - Parameters:
    ///   - context: The drawing context in plot coordinates.
    ///   - transformerProvider: Supplies the current data-to-plot transform.
    func drawTechnicalIndicators(context: CGContext, transformerProvider: AffineTransformerProvider) {
        let transformer = transformerProvider.transformer

        for indicator in dataProvider.technicalIndicators {
            let linePath = CGMutablePath()
            var isFirstPoint = true

            for point in indicator.dataPoints {
                let pixelPoint = transformer.pixelForValue(DoublePrecisionPoint(x: point.x, y: point.y))
                guard pixelPoint.x.isFinite, pixelPoint.y.isFinite else {
                    isFirstPoint = true
                    continue
                }

                if isFirstPoint {
                    linePath.move(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y))
                    isFirstPoint = false
                } else {
                    linePath.addLine(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y))
                }
            }

            context.saveGState()
            defer { context.restoreGState() }

            context.addPath(linePath)
            context.setStrokeColor(indicator.color.cgColor)
            context.setLineWidth(2.0)
            context.strokePath()
        }
    }
}
