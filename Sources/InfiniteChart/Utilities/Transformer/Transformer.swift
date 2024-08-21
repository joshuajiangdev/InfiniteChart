//
//  Transformer.swift
//  
//
//  Created by Joshua Jiang on 8/21/24.
//

import UIKit
import Accelerate

public struct DoublePrecisionPoint: Equatable {
    let x: Double
    let y: Double
}

public protocol Transformer: Equatable {
    func valueForTouchPoint(_ point: CGPoint) -> DoublePrecisionPoint
    func pixelForValue(_ point: DoublePrecisionPoint) -> CGPoint
}

public struct AccelerateTransformer: Transformer {
    
    let valueToPixelMatrix: [Double]
    let pixelToValueMatrix: [Double]
    
    public func valueForTouchPoint(_ point: CGPoint) -> DoublePrecisionPoint {
        var result = [Double](repeating: 0, count: 3)
        let input = [Double(point.x), Double(point.y), 1]

        vDSP_mmulD(input, 1, pixelToValueMatrix, 1, &result, 1, 1, 3, 3)
        
        return DoublePrecisionPoint(x: result[0], y: result[1])
    }
    
    public func pixelForValue(_ point: DoublePrecisionPoint) -> CGPoint {
        var result = [Double](repeating: 0, count: 3)
        let input = [Double(point.x), Double(point.y), 1]
        
        vDSP_mmulD(input, 1, valueToPixelMatrix, 1, &result, 1, 1, 3, 3)
        
        return CGPoint(x: result[0], y: result[1])
    }
}
