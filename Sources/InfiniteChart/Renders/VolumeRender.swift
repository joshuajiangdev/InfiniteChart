//
//  VolumeRender.swift
//  
//
//  Created by Joshua Jiang on 8/25/24.
//

import CoreGraphics

class VolumeRender {
    let dataProvider: any VolumeDataProvider
    
    init(dataProvider: any VolumeDataProvider) {
        self.dataProvider = dataProvider
    }
    
    func drawVolumeChart(context: CGContext, transformerProvider: AccelerateTransformerProvider, rect: CGRect) {
        let transformer = transformerProvider.transformer
        
        let xValues = ChartRenderSamples.xValues(dataProvider: dataProvider, transformerProvider: transformerProvider)
        let samples = xValues.compactMap { x -> (x: Double, volume: Double, color: ChartColor)? in
            guard let value = dataProvider.getVolumeValueAndColor(for: x) else { return nil }
            return (x: x, volume: value.volume, color: value.color)
        }
        guard let maxVolume = samples.map(\.volume).max(), maxVolume > 0 else { return }

        let barWidth = ChartRenderSamples.barWidth(
            dataProvider: dataProvider, transformerProvider: transformerProvider, legacyWidth: 2
        )
        let volumeHeight = rect.height
        
        for sample in samples {
            let startPoint = transformer.pixelForValue(DoublePrecisionPoint(x: sample.x, y: 0))
            let barHeight = CGFloat(sample.volume / maxVolume) * volumeHeight
            
            let barRect = CGRect(x: startPoint.x - barWidth/2,
                                 y: rect.maxY - barHeight,
                                 width: barWidth,
                                 height: barHeight)
            
            context.setFillColor(sample.color.cgColor)
            context.fill(barRect)
        }
    }
}
