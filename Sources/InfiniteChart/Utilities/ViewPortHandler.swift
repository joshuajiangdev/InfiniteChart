import Foundation
import CoreGraphics
import Combine

public class ViewPortHandler {
    
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

    func setChartDimens(width: CGFloat, height: CGFloat) {
        chartWidth = width
        chartHeight = height
        contentRect.size = CGSize(width: chartWidth, height: chartHeight)
    }


    func zoom(scaleX: CGFloat, scaleY: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        let tx = x - viewPortMatrix.tx
        let ty = y - viewPortMatrix.ty
        
        var temp = viewPortMatrix.translatedBy(x: tx, y: ty).scaledBy(x: scaleX, y: scaleY).translatedBy(x: -tx, y: -ty)
        limitTransAndScale(matrix: &temp, content: contentRect)
        viewPortMatrix = temp
    }

    func translate(pt: CGPoint) {
        var temp = viewPortMatrix.translatedBy(x: -pt.x, y: -pt.y)
        limitTransAndScale(matrix: &temp, content: contentRect)
        viewPortMatrix = temp
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
