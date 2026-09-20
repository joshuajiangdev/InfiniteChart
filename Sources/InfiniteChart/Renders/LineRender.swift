//
//  LineRender.swift
//  
//
//  Created by Joshua Jiang on 8/22/24.
//

import CoreGraphics

final class LineRender {
    let dataProvider: any LineChartDataProvider
    
    init(dataProvider: any LineChartDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawSimpleLineChart(context: CGContext, transformerProvider: AffineTransformerProvider) {
        let linePath = CGMutablePath()
        let transformer = transformerProvider.transformer
        guard let viewport = transformerProvider.viewport(for: transformer) else { return }
        
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
