//
//  LineRender.swift
//  
//
//  Created by Joshua Jiang on 8/22/24.
//

import UIKit

protocol DataProvider {
    func value(at index: Double) -> Double?
}

class LineDataProvider: DataProvider {
    let dataFetcher: BTCDataFetcher
    
    init(dataFetcher: BTCDataFetcher) {
        self.dataFetcher = dataFetcher
    }
    
    func value(at index: Double) -> Double? {
        dataFetcher.getData(for: index)
    }
}

final class LineRender {
    let dataProvider: LineDataProvider
    
    init(dataProvider: LineDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawSimpleLineChart(context: CGContext, transformerProvider: AccelerateTransformerProvider) {
        let phaseY: CGFloat = 1.0 // Assuming full phase, adjust if needed
        
        let linePath = CGMutablePath()
        let transformer = transformerProvider.transformer
        
        var startX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x.rounded(.up)
        startX = dataProvider.dataFetcher.getClosestXValue(to: startX, seekBelow: true) ?? startX
        var endX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: transformerProvider.chartWidth, y: 0)).x.rounded(.down)
        endX = dataProvider.dataFetcher.getClosestXValue(to: endX, seekBelow: false) ?? endX
        let step: Double = 60*1000 // Adjust step size as needed
        
        var isFirstPoint = true
        
        for x in stride(from: startX, to: endX, by: step) {
            guard let y = dataProvider.value(at: x) else {
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
        context.setStrokeColor(UIColor.blue.cgColor) // Set line color
        context.setLineWidth(2.0) // Set line width
        context.strokePath()
    }
}
