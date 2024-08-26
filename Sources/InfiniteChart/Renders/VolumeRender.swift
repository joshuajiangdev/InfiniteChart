//
//  VolumeRender.swift
//  
//
//  Created by Joshua Jiang on 8/25/24.
//

import UIKit

class VolumeRender {
    let dataProvider: any VolumeDataProvider
    
    init(dataProvider: any VolumeDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawVolumeChart(context: CGContext, transformerProvider: AccelerateTransformerProvider, rect: CGRect) {
        let transformer = transformerProvider.transformer
        
        var startX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: 0, y: 0)).x.rounded(.up)
        startX = dataProvider.getClosestXValue(to: startX, seekBelow: true, offset: 1) ?? startX
        var endX = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: transformerProvider.chartWidth, y: 0)).x.rounded(.down)
        endX = dataProvider.getClosestXValue(to: endX, seekBelow: false, offset: 1) ?? endX
        let step: Double = 60*1000 // Adjust step size as needed
        
        // Calculate max volume in visible range
        var maxVolume: Double = 0
        for x in stride(from: startX, to: endX, by: step) {
            if let (volume, _) = dataProvider.getVolumeValueAndColor(for: x) {
                maxVolume = max(maxVolume, volume)
            }
        }
        
        guard maxVolume > 0 else { return }
        
        let barWidth: CGFloat = 2.0
        let volumeHeight = rect.height
        
        for x in stride(from: startX, to: endX, by: step) {
            guard let (volume, color) = dataProvider.getVolumeValueAndColor(for: x) else { continue }
            
            let startPoint = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: 0))
            let barHeight = CGFloat(volume / maxVolume) * volumeHeight
            
            let barRect = CGRect(x: startPoint.x - barWidth/2,
                                 y: rect.maxY - barHeight,
                                 width: barWidth,
                                 height: barHeight)
            
            context.setFillColor(color.cgColor)
            context.fill(barRect)
        }
    }
}