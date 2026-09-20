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
    
    func drawCandleStickChart(context: CGContext, transformerProvider: AffineTransformerProvider) {
        let transformer = transformerProvider.transformer
        guard let viewport = transformerProvider.viewport(for: transformer) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)

        for x in dataProvider.renderingXValues(in: viewport.visibleXRange) {
            guard let candleStick = dataProvider.getCandleStickDataPoint(for: x),
                  candleStick.high.isFinite, candleStick.low.isFinite,
                  candleStick.open.isFinite, candleStick.close.isFinite else {
                continue
            }
            
            let high = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.high))
            let low = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.low))
            let open = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.open))
            let close = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: candleStick.close))
            guard high.x.isFinite, high.y.isFinite, low.y.isFinite,
                  open.y.isFinite, close.y.isFinite else { continue }
            
            // Draw the wick
            context.move(to: CGPoint(x: high.x, y: high.y))
            context.addLine(to: CGPoint(x: low.x, y: low.y))
            context.setStrokeColor(candleStick.color.cgColor)
            context.strokePath()
            
            // Draw the body
            let bodyRect = CGRect(x: open.x - 2, y: min(open.y, close.y),
                                  width: 4, height: max(1, abs(close.y - open.y)))
            context.setFillColor(candleStick.color.cgColor)
            context.fill(bodyRect)
        }
    }
}
