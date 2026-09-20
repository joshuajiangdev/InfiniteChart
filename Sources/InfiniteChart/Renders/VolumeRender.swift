//
//  VolumeRender.swift
//  
//
//  Created by Joshua Jiang on 8/25/24.
//

import CoreGraphics

class VolumeRender {
    let dataProvider: any VolumeDataProvider
    
    /// Creates a renderer that reads volume values and colors from the provider.
    init(dataProvider: any VolumeDataProvider) {
        self.dataProvider = dataProvider
    }
    
    /// Draws two-point volume bars scaled to the largest valid visible volume.
    ///
    /// Fetches each visible sample once and excludes missing, nonfinite, nonpositive,
    /// and offscreen volumes from normalization. Bars rise from the rectangle's
    /// bottom edge, independently of the price Y scale. Restores the graphics state
    /// after drawing; the caller controls clipping.
    ///
    /// - Parameters:
    ///   - context: The drawing context in plot coordinates.
    ///   - transformerProvider: Supplies the current X transform and visible X range.
    ///   - rect: The volume panel in plot coordinates; its height sets the tallest bar.
    func drawVolumeChart(context: CGContext, transformerProvider: AffineTransformerProvider, rect: CGRect) {
        let transformer = transformerProvider.transformer
        guard let viewport = transformerProvider.viewport,
              !rect.isEmpty, rect.height.isFinite else { return }

        let volumes = dataProvider.renderingXValues(in: viewport.visibleXRange).compactMap { x -> (x: Double, volume: Double, color: ChartColor)? in
            guard viewport.visibleXRange.contains(x),
                  let (volume, color) = dataProvider.getVolumeValueAndColor(for: x),
                  volume.isFinite, volume > 0 else { return nil }
            return (x, volume, color)
        }
        guard let maxVolume = volumes.map(\.volume).max() else { return }

        context.saveGState()
        defer { context.restoreGState() }
        
        let barWidth: CGFloat = 2.0
        let volumeHeight = rect.height
        
        for (x, volume, color) in volumes {
            let startPoint = transformer.pixelForValue(DoublePrecisionPoint(x: x, y: 0))
            guard startPoint.x.isFinite else { continue }
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
