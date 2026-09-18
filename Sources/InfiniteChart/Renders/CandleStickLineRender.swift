//
//  CandleStickLineRender.swift
//  
//
//  Created by Joshua Jiang on 8/24/24.
//

import CoreGraphics

class CandleStickLineRender {
    let dataProvider: any CandleStickDataProvider
    
    init(dataProvider: any CandleStickDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawCandleStickChart(context: CGContext, transformerProvider: AccelerateTransformerProvider) {
        let transformer = transformerProvider.transformer
        
        let xValues = ChartRenderSamples.xValues(dataProvider: dataProvider, transformerProvider: transformerProvider)
        let bodyWidth = ChartRenderSamples.barWidth(
            dataProvider: dataProvider, transformerProvider: transformerProvider, legacyWidth: 4
        )
        
        for x in xValues {
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
            let bodyRect = CGRect(x: open.x - bodyWidth / 2, y: min(open.y, close.y),
                                  width: bodyWidth, height: abs(close.y - open.y))
            context.setFillColor(candleStick.color.cgColor)
            context.fill(bodyRect)
        }
    }
}
