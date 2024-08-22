//
//  AccelerateTransformer.swift
//  
//
//  Created by Joshua Jiang on 8/20/24.
//

import UIKit
import Foundation
import Accelerate
import Combine

public struct DataRanges {
    let chartXMin: Double
    let deltaX: Double
    let chartYMin: Double
    let deltaY: Double
}

final public class AccelerateTransformerProvider: TransformerProviding {
    
    private(set) var chartWidth: CGFloat = 0
    private(set) var chartHeight: CGFloat = 0
    
    private(set) var valueToPixelMatrix: [Double] {
        didSet {
            transformer = AccelerateTransformer(valueToPixelMatrix: valueToPixelMatrix, pixelToValueMatrix: valueToPixelMatrix.invert())
        }
    }
    
    @Published
    private(set) var transformer: AccelerateTransformer
    
    lazy var transformerStream: AnyPublisher<AccelerateTransformer, Never> = $transformer.eraseToAnyPublisher()
    
    public init(
        size: CGSize,
        dataRanges: DataRanges
    ) {
        chartWidth = size.width
        chartHeight = size.height
        
        let scaleX = (chartWidth / dataRanges.deltaX)
        let scaleY = (chartHeight / dataRanges.deltaY)
        
        let matrixA = [
            scaleX, 0, 0,
            0, -scaleY, 0,
            -dataRanges.chartXMin * scaleX, -dataRanges.chartYMin * scaleY, 1
        ]
        
        let matrixB = [
            1, 0, 0,
            0, 1, 0,
            0, Double(chartHeight), 1
        ]
        
        var result = [Double](repeating: 0, count: 9)
        vDSP_mmulD(matrixA, 1, matrixB, 1, &result, 1, 3, 3, 3)
        
        valueToPixelMatrix = result

        transformer = AccelerateTransformer(valueToPixelMatrix: valueToPixelMatrix, pixelToValueMatrix: valueToPixelMatrix.invert())
    }
    
    func setChartDimens(width: CGFloat, height: CGFloat) {
        chartWidth = width
        chartHeight = height
    }
    
    func prepareMatrixValuePx(dataRanges: DataRanges) {
        let scaleX = (chartWidth / dataRanges.deltaX)
        let scaleY = (chartHeight / dataRanges.deltaY)
        
        let matrixA = [
            scaleX, 0, 0,
            0, -scaleY, 0,
            -dataRanges.chartXMin * scaleX, -dataRanges.chartYMin * scaleY, 1
        ]
        
        let matrixB = [
            1, 0, 0,
            0, 1, 0,
            0, Double(chartHeight), 1
        ]
        
        var result = [Double](repeating: 0, count: 9)
        vDSP_mmulD(matrixA, 1, matrixB, 1, &result, 1, 3, 3, 3)
        
        valueToPixelMatrix = result
    }
    
    public func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        let valuePoint = self.transformer.valueForTouchPoint(CGPoint(x: x, y: y))
        
        let newTx = (1-scaleX)*valuePoint.x*valueToPixelMatrix[0] + valueToPixelMatrix[6]
        let newTy = (1-scaleY)*valuePoint.y*valueToPixelMatrix[4] + valueToPixelMatrix[7]

        var newMatrix = valueToPixelMatrix
        newMatrix[0] = valueToPixelMatrix[0] * scaleX
        newMatrix[4] = valueToPixelMatrix[4] * scaleY
        newMatrix[6] = newTx
        newMatrix[7] = newTy
        
        valueToPixelMatrix = newMatrix
    }
    
    public func translate(delta: CGPoint) {
        let newTx = valueToPixelMatrix[6] + delta.x
        let newTy = valueToPixelMatrix[7] + delta.y
        
        var newMatrix = valueToPixelMatrix

        newMatrix[6] = newTx
        newMatrix[7] = newTy
        
        valueToPixelMatrix = newMatrix
    }
}

extension Array where Element == Double {
    func invert() -> [Double] {
        var inMatrix = self
        var N = __CLPK_integer(sqrt(Double(self.count)))
        var pivots = [__CLPK_integer](repeating: 0, count: Int(N))
        var workspace = [Double](repeating: 0.0, count: Int(N))
        var error : __CLPK_integer = 0

        withUnsafeMutablePointer(to: &N) {
            dgetrf_($0, $0, &inMatrix, $0, &pivots, &error)
            dgetri_($0, &inMatrix, $0, &pivots, &workspace, $0, &error)
        }
        return inMatrix
    }
    
}
