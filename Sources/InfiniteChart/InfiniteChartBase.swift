import UIKit

public class InfiniteChartBase: UIView {
    
    let xAxisHeight: CGFloat = 50
    let yAxisWidth: CGFloat = 50

    let dataRanges = DataRanges(chartXMin: 0, deltaX: 100, chartYMin: 0, deltaY: 100)
    lazy var transformerProvider = AccelerateTransformerProvider(
        size: bounds.size,
        dataRanges: dataRanges
    )
    lazy var xAxisView = XAxisView()
    lazy var yAxisView = YAxisView()
    lazy var chartBaseView = ChartBaseView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .red

        addSubview(xAxisView)
        addSubview(yAxisView)
        addSubview(chartBaseView)
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
        
        yAxisView.frame = CGRect(
            x: bounds.size.width - yAxisWidth,
            y: 0,
            width: yAxisWidth,
            height: bounds.size.height - xAxisHeight
        )
        
        chartBaseView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.size.width - yAxisWidth,
            height: bounds.size.height - xAxisHeight
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    public func setup() {
        xAxisView.transformerStream = transformerProvider.transformerStream
        xAxisView.transformerProvider = transformerProvider
        xAxisView.setup()
        
        yAxisView.transformerStream = transformerProvider.transformerStream
        yAxisView.transformerProvider = transformerProvider
        yAxisView.setup()
        
        chartBaseView.transformerStream = transformerProvider.transformerStream
        chartBaseView.transformerProvider = transformerProvider
    }
}
