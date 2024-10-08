//
//  LineRender.swift
//  
//
//  Created by Joshua Jiang on 8/22/24.
//

import UIKit

final class LineRender {
    let dataProvider: any LineChartDataProvider
    
    init(dataProvider: any LineChartDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawSimpleLineChart(context: CGContext, transformerProvider: AccelerateTransformerProvider) {
        let phaseY: CGFloat = 1.0 // Assuming full phase, adjust if needed
        
        let linePath = CGMutablePath()
        let transformer = transformerProvider.transformer
        
        var startX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x.rounded(.up)
        startX = dataProvider.getClosestXValue(to: startX, seekBelow: true, offset: 1) ?? startX
        var endX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: transformerProvider.chartWidth, y: 0)).x.rounded(.down)
        endX = dataProvider.getClosestXValue(to: endX, seekBelow: false, offset: 1) ?? endX
        let step: Double = 60*1000 // Adjust step size as needed
        
        var isFirstPoint = true
        
        for x in stride(from: startX, to: endX, by: step) {
            guard let y = dataProvider.getYValue(for: x) else {
                continue
            }
            
            let pixelPoint = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: y))
            
            if isFirstPoint {
                linePath.move(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y * phaseY))
                isFirstPoint = false
            } else {
                linePath.addLine(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y * phaseY))
            }
        }
        
        // Draw the path
        context.saveGState()
        defer { context.restoreGState() }
        
        context.addPath(linePath)
        context.setStrokeColor(UIColor.yellow.cgColor) // Change color to yellow for better visibility
        context.setLineWidth(3.0) // Increase line width to 3.0
        context.strokePath()
    }
}