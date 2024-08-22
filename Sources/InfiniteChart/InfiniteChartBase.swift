import UIKit

public class InfiniteChartBase: UIView {
    
    let xAxisHeight: CGFloat = 50
    let yAxisWidth: CGFloat = 50

    let dataRanges = DataRanges(chartXMin: 0, deltaX: 100, chartYMin: 0, deltaY: 100)
    lazy var viewPortHandler = ViewPortHandler(width: bounds.size.width - yAxisWidth, height: bounds.size.height - xAxisHeight)
    lazy var transformerProvider = AccelerateTransformerProvider(
        size: bounds.size,
        dataRanges: dataRanges
    )
    lazy var xAxisView = XAxisView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .red

        addSubview(xAxisView)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        transformerProvider.setChartDimens(width: bounds.width - yAxisWidth, height: bounds.height - xAxisHeight)
        transformerProvider.prepareMatrixValuePx(dataRanges: dataRanges)
        
        xAxisView.frame = CGRect(
            x: 0,
            y: bounds.size.height - xAxisHeight,
            width: bounds.size.width - yAxisWidth,
            height: xAxisHeight
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    public func setup() {
        xAxisView.transformerStream = transformerProvider.transformerStream
        xAxisView.transformerProvider = transformerProvider
        xAxisView.setup()
    }
}
