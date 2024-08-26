//
//  CandleStickLineRender.swift
//  
//
//  Created by Joshua Jiang on 8/24/24.
//

import UIKit

class CandleStickLineRender {
    let dataProvider: any CandleStickDataProvider
    
    init(dataProvider: any CandleStickDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawCandleStickChart(context: CGContext, transformerProvider: AccelerateTransformerProvider) {
        let transformer = transformerProvider.transformer
        
        var startX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x.rounded(.up)
        startX = dataProvider.getClosestXValue(to: startX, seekBelow: true, offset: 1) ?? startX
        var endX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: transformerProvider.chartWidth, y: 0)).x.rounded(.down)
        endX = dataProvider.getClosestXValue(to: endX, seekBelow: false, offset: 1) ?? endX
        let step: Double = 60*1000 // Adjust step size as needed
        
        for x in stride(from: startX, to: endX, by: step) {
            guard let candleStick = dataProvider.getCandleStickDataPoint(for: x) else {
                continue
            }
            
            let high = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.high))
            let low = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.low))
            let open = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.open))
            let close = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.close))
            
            // Draw the wick
            context.move(to: CGPoint(x: high.x, y: high.y))
            context.addLine(to: CGPoint(x: low.x, y: low.y))
            context.setStrokeColor(candleStick.color.cgColor)
            context.strokePath()
            
            // Draw the body
            let bodyRect = CGRect(x: open.x - 2, y: min(open.y, close.y),
                                  width: 4, height: abs(close.y - open.y))
            context.setFillColor(candleStick.color.cgColor)
            context.fill(bodyRect)
        }
    }
}