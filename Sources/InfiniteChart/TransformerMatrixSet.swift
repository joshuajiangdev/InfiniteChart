//
//  TransformerMatrixSet.swift
//  
//
//  Created by Joshua Jiang on 8/17/24.
//


import Foundation
import CoreGraphics

struct TransformerMatrixSet {
    let valueToPixelMatrix: CGAffineTransform
    let pixelToValueMatrix: CGAffineTransform
}

extension TransformerMatrixSet {
    
    func valueForTouchPoint(_ point: CGPoint) -> CGPoint {
        return point.applying(pixelToValueMatrix)
    }
    
    func pixelForValue(_ point: CGPoint) -> CGPoint {
        return point.applying(valueToPixelMatrix)
    }
}

