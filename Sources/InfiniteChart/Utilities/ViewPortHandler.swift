import Foundation
import CoreGraphics
import Combine

public class ViewPortHandler: Equatable {
    
    public static func == (lhs: ViewPortHandler, rhs: ViewPortHandler) -> Bool {
        lhs.viewPortMatrix == rhs.viewPortMatrix &&
        lhs.chartHeight == rhs.chartHeight &&
        lhs.chartWidth == rhs.chartWidth
    }
    
    // viewPortMatrix stream
    @Published var viewPortMatrix: CGAffineTransform = .identity

    /// this rectangle defines the area in which graph values can be drawn
    private var contentRect = CGRect.zero

    private(set) var chartWidth: CGFloat = 0
    private(set) var chartHeight: CGFloat = 0

    private let minScaleX: CGFloat = 1.0
    private let minScaleY: CGFloat = 1.0

    private let maxScaleX = CGFloat.greatestFiniteMagnitude
    private let maxScaleY = CGFloat.greatestFiniteMagnitude
    
    var canZoomOutMoreX: Bool {
        return viewPortMatrix.a > minScaleX
    }
    var canZoomInMoreX: Bool {
        return viewPortMatrix.a < maxScaleX
    }
    
    public init(width: CGFloat, height: CGFloat) {
        setChartDimens(width: width, height: height)
    }

    func setChartDimens(width: CGFloat, height: CGFloat) {
        chartWidth = width
        chartHeight = height
        contentRect.size = CGSize(width: chartWidth, height: chartHeight)
    }


    public func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        
        let point = CGPoint(x: x, y: y)
        let oldMatrix = viewPortMatrix
        let scaleDelta = round(scaleX*1000)/1000
        var newTx = (1-scaleDelta)*x*oldMatrix.a + oldMatrix.tx
        newTx = round(newTx*1000)/1000
        
        var newMatrix = oldMatrix
        newMatrix.a = oldMatrix.a * scaleDelta
        newMatrix.tx = newTx
//            .scaledBy(
//                x: newScale,
//                y: scaleY
//            ).translatedBy(
//                x: newTx,
//                y: (1-scaleY)*y*oldMatrix.c
//            )
        
        print(point)
        print(scaleDelta, newTx)
        print(oldMatrix.a,oldMatrix.tx)
        print(newMatrix.a,newMatrix.tx)
        print("Before: \(point.applying(oldMatrix).x)")
        print("After: \(point.applying(newMatrix).x)")
        print("------------")
        viewPortMatrix = newMatrix
    }

    public func translate(pt: CGPoint) {
        var temp = viewPortMatrix.translatedBy(x: -pt.x, y: 0)
        limitTransAndScale(matrix: &temp, content: contentRect)
        viewPortMatrix = temp
    }

    public func update(newMatrix: CGAffineTransform) {
        var matrix = newMatrix
        limitTransAndScale(matrix: &matrix, content: contentRect)
        viewPortMatrix = matrix
    }

    private func limitTransAndScale(matrix: inout CGAffineTransform, content: CGRect) {
        // min scale-x is 1
        let scaleX = min(max(minScaleX, matrix.a), maxScaleX)
        
        // min scale-y is 1
        let scaleY = min(max(minScaleY,  matrix.d), maxScaleY)
        
        matrix.a = scaleX
        matrix.d = scaleY
    }
}
