import Foundation
import CoreGraphics
import Combine

class Transformer {
    
    @Published var transformMatrixSet: TransformerMatrixSet = TransformerMatrixSet(
        valueToPixelMatrix: CGAffineTransform.identity,
        pixelToValueMatrix: CGAffineTransform.identity
    )
    
    var disPosable = Set<AnyCancellable>()
    
    var matrixValueToPx: CGAffineTransform {
        didSet {
            refreshMatrixSet()
        }
    }
    
    var matrixOffset: CGAffineTransform {
        didSet {
            refreshMatrixSet()
        }
    }
    
    var viewPortHandler: ViewPortHandler
    
    init(viewPortHandler: ViewPortHandler) {
        self.viewPortHandler = viewPortHandler
        self.matrixValueToPx = CGAffineTransform.identity
        self.matrixOffset = CGAffineTransform.identity
        setupObservers()
    }
    
    func prepareMatrixValuePx(
        chartXMin: Double,
        deltaX: CGFloat,
        chartYMin: Double,
        deltaY: CGFloat
    ) {
        let scaleX = (viewPortHandler.chartWidth / deltaX)
        let scaleY = (viewPortHandler.chartHeight / deltaY)
        
        matrixValueToPx = CGAffineTransform.identity
            .scaledBy(x: scaleX, y: -scaleY)
            .translatedBy(x: CGFloat(-chartXMin), y: CGFloat(-chartYMin))
    }
    
    func prepareMatrixOffset(inverted: Bool)
    {
        if !inverted
        {
            matrixOffset = CGAffineTransform(translationX: 0, y: viewPortHandler.chartHeight)
        }
        else
        {
            matrixOffset = CGAffineTransform(scaleX: 1.0, y: -1.0)
        }
    }
    
    private func getMatrixValueToPx(viewPortMatrix: CGAffineTransform) -> CGAffineTransform {
        return matrixValueToPx.concatenating(viewPortMatrix).concatenating(matrixOffset)
    }
        
    private func setupObservers() {
        viewPortHandler.$viewPortMatrix.sink { [weak self] viewPortMatrix in
            guard let strongSelf = self else { return }
            strongSelf.refreshMatrixSet(viewPortMatrix: viewPortMatrix)
        }
        .store(in: &disPosable)
    }
    
    private func refreshMatrixSet(viewPortMatrix: CGAffineTransform? = nil) {
        let matrixValueToPx = getMatrixValueToPx(viewPortMatrix: viewPortMatrix ?? viewPortHandler.viewPortMatrix)
        
        transformMatrixSet = TransformerMatrixSet(
            valueToPixelMatrix: matrixValueToPx,
            pixelToValueMatrix: matrixValueToPx.inverted()
        )
    }
}
