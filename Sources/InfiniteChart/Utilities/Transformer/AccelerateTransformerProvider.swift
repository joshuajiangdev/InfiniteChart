//
//  AccelerateTransformer.swift
//  
//
//  Created by Joshua Jiang on 8/20/24.
//

import Foundation
import CoreGraphics
import Accelerate
import Combine

final public class AccelerateTransformerProvider: TransformerProviding {
    
    let initDataRanges: DataRanges
    
    private(set) var chartWidth: CGFloat = 0
    private(set) var chartHeight: CGFloat = 0

    /// A snapshot derived from the existing transform and plot dimensions.
    func viewport(for transformer: AccelerateTransformer) -> ChartViewport? {
        let size = CGSize(width: chartWidth, height: chartHeight)
        guard size.width > 0, size.height > 0 else { return nil }
        let topLeft = transformer.valueForTouchPoint(.zero)
        let bottomRight = transformer.valueForTouchPoint(CGPoint(x: size.width, y: size.height))
        guard topLeft.x.isFinite, topLeft.y.isFinite, bottomRight.x.isFinite, bottomRight.y.isFinite,
              topLeft.x < bottomRight.x, bottomRight.y < topLeft.y else { return nil }
        return ChartViewport(visibleXRange: topLeft.x...bottomRight.x,
                             visibleYRange: bottomRight.y...topLeft.y, plotSize: size)
    }

    /// Optional horizontal span limits, expressed in the provider's X units.
    public var xSpanLimits: ClosedRange<Double>?

    
    private(set) var valueToPixelMatrix: [Double] {
        didSet {
            let invertedMatrix = valueToPixelMatrix.invert()
            
            transformer = AccelerateTransformer(valueToPixelMatrix: valueToPixelMatrix, pixelToValueMatrix: invertedMatrix)
        }
    }
    
    @Published
    private(set) var transformer: AccelerateTransformer
    
    lazy var transformerStream: AnyPublisher<AccelerateTransformer, Never> = $transformer.eraseToAnyPublisher()
    
    public init(
        size: CGSize,
        dataRanges: DataRanges
    ) {
        self.initDataRanges = dataRanges
        chartWidth = size.width
        chartHeight = size.height
        
        let scaleX = (chartWidth / dataRanges.deltaX)
        let scaleY = (chartHeight / dataRanges.deltaY)
        
        let matrixA = [
            scaleX, 0, 0,
            0, -scaleY, 0,
            -dataRanges.chartXMin * scaleX, dataRanges.chartYMin * scaleY, 1
        ]
        
        let matrixB = [
            1, 0, 0,
            0, 1, 0,
            0, Double(chartHeight), 1
        ]
        
        var result = [Double](repeating: 0, count: 9)
        vDSP_mmulD(matrixA, 1, matrixB, 1, &result, 1, 3, 3, 3)
        
        valueToPixelMatrix = result

        let invertedMatrix = valueToPixelMatrix.invert()
        transformer = AccelerateTransformer(valueToPixelMatrix: valueToPixelMatrix, pixelToValueMatrix: invertedMatrix)
    }
    
    func setChartDimens(width: CGFloat, height: CGFloat) {
        chartWidth = width
        chartHeight = height
    }
    
    func prepareMatrixValuePx(dataRanges: DataRanges) {
        guard dataRanges.chartXMin.isFinite, dataRanges.chartYMin.isFinite,
              dataRanges.deltaX.isFinite, dataRanges.deltaX > 0,
              dataRanges.deltaY.isFinite, dataRanges.deltaY > 0 else { return }
        var horizontalSpan = dataRanges.deltaX
        if let limits = xSpanLimits,
           limits.lowerBound.isFinite, limits.lowerBound > 0, limits.upperBound.isFinite {
            horizontalSpan = min(max(horizontalSpan, limits.lowerBound), limits.upperBound)
        }
        let horizontalMinimum = dataRanges.chartXMin + (dataRanges.deltaX - horizontalSpan) / 2
        let scaleX = (chartWidth / horizontalSpan)
        let scaleY = (chartHeight / dataRanges.deltaY)
        
        let matrixA = [
            scaleX, 0, 0,
            0, -scaleY, 0,
            -horizontalMinimum * scaleX, dataRanges.chartYMin * scaleY, 1
        ]
        
        let matrixB = [
            1, 0, 0,
            0, 1, 0,
            0, Double(chartHeight), 1
        ]
        
        var result = [Double](repeating: 0, count: 9)
        vDSP_mmulD(matrixA, 1, matrixB, 1, &result, 1, 3, 3, 3)
        
        apply(result)
    }
    
    func setVisibleYRange(_ range: ClosedRange<Double>) {
        let span = range.upperBound - range.lowerBound
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              span.isFinite, span > 0 else { return }
        let scale = chartHeight / span
        var matrix = valueToPixelMatrix
        // Retain the X coefficients instead of rebuilding them from an inverse
        // transform or reapplying horizontal limits during a vertical-only fit.
        matrix[4] = -scale
        matrix[7] = chartHeight + range.lowerBound * scale
        apply(matrix)
    }

    public func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        guard scaleX.isFinite, scaleX > 0, scaleY.isFinite, scaleY > 0,
              x.isFinite, y.isFinite else { return }
        var horizontalScale = scaleX
        // Only constrain X when the gesture requests horizontal scaling.
        if scaleX != 1, let limits = xSpanLimits,
           limits.lowerBound.isFinite, limits.lowerBound > 0, limits.upperBound.isFinite {
            let currentSpan = chartWidth / valueToPixelMatrix[0]
            let requestedSpan = currentSpan / scaleX
            let limitedSpan = min(max(requestedSpan, limits.lowerBound), limits.upperBound)
            horizontalScale = currentSpan / limitedSpan
        }
        let valuePoint = self.transformer.valueForTouchPoint(CGPoint(x: x, y: y))
        
        let newTx = (1-horizontalScale)*valuePoint.x*valueToPixelMatrix[0] + valueToPixelMatrix[6]
        let newTy = (1-scaleY)*valuePoint.y*valueToPixelMatrix[4] + valueToPixelMatrix[7]

        var newMatrix = valueToPixelMatrix
        let newScaleX = valueToPixelMatrix[0] * horizontalScale
        newMatrix[0] = newScaleX
        newMatrix[4] = valueToPixelMatrix[4] * scaleY
        newMatrix[6] = newTx
        newMatrix[7] = newTy
        apply(newMatrix)
    }
    
    public func translate(delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        let newTx = valueToPixelMatrix[6] + delta.x
        let newTy = valueToPixelMatrix[7] + delta.y
        
        var newMatrix = valueToPixelMatrix

        newMatrix[6] = newTx
        newMatrix[7] = newTy
        
        apply(newMatrix)
    }

    private func apply(_ matrix: [Double]) {
        guard matrix.allSatisfy(\.isFinite), matrix[0] > 0, matrix[4] < 0,
              matrix != valueToPixelMatrix else { return }
        // Reject transforms that cannot produce finite data coordinates.
        guard matrix.invert().allSatisfy(\.isFinite) else { return }
        valueToPixelMatrix = matrix
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
