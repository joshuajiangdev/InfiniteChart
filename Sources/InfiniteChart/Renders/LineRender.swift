//
//  LineRender.swift
//  
//
//  Created by Joshua Jiang on 8/22/24.
//

import CoreGraphics

final class LineRender {
    let dataProvider: any LineChartDataProvider
    
    /// Creates a renderer that reads line samples from the provider.
    init(dataProvider: any LineChartDataProvider) {
        self.dataProvider = dataProvider
    }
    
    /// Draws a yellow, three-point line through available samples around the viewport.
    ///
    /// Missing or nonfinite values and transformed coordinates break the path so
    /// valid segments on either side remain disconnected. Restores the graphics
    /// state after drawing; the caller controls clipping.
    ///
    /// - Parameters:
    ///   - context: The drawing context in plot coordinates.
    ///   - transformerProvider: Supplies the current transform and visible X range.
    func drawSimpleLineChart(context: CGContext, transformerProvider: AffineTransformerProvider) {
        let linePath = CGMutablePath()
        let transformer = transformerProvider.transformer
        guard let viewport = transformerProvider.viewport else { return }
        
        var isFirstPoint = true
        
        for x in dataProvider.renderingXValues(in: viewport.visibleXRange) {
            guard let y = dataProvider.getYValue(for: x), y.isFinite else {
                isFirstPoint = true
                continue
            }
            
            let pixelPoint = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: y))
            guard pixelPoint.x.isFinite, pixelPoint.y.isFinite else {
                isFirstPoint = true
                continue
            }
            
            if isFirstPoint {
                linePath.move(to: pixelPoint)
                isFirstPoint = false
            } else {
                linePath.addLine(to: pixelPoint)
            }
        }
        
        // Draw the path
        context.saveGState()
        defer { context.restoreGState() }
        
        context.addPath(linePath)
        context.setStrokeColor(ChartColor.yellow.cgColor)
        context.setLineWidth(3.0)
        context.strokePath()
    }
}
