import UIKit
import Combine

public class InfiniteChartBase: UIView {
    
    let xAxisHeight: CGFloat = 50
    let yAxisWidth: CGFloat = 50

    var disposeBag = Set<AnyCancellable>()
    
    // MARK: - Private Properties
    
    let dataProvider: any ChartDataProvider
    
    // TODO: Clear config/setup flow
    lazy var transformerProvider: AccelerateTransformerProvider = {
        guard let dataRanges = dataProvider.getInitDataRanges() else {
            fatalError("Failed to get data ranges from BTCDataFetcher")
        }
        
        return AccelerateTransformerProvider(
            size: bounds.size,
            dataRanges: dataRanges
        )
    }()
    
    private func setupObservable() {
        transformerProvider.$transformer.sink(receiveValue: { _ in
            self.setNeedsDisplay()
        }).store(in: &disposeBag)
    }
    
    lazy var xAxisView = XAxisView()
    lazy var yAxisView = YAxisView()
    lazy var chartBaseView = ChartBaseView()
    lazy var lineRender = LineRender(dataProvider: dataProvider)
    
    public init(frame: CGRect, dataProvider: any ChartDataProvider){
        self.dataProvider = dataProvider
        
        super.init(frame: frame)
        
        backgroundColor = .red

        addSubview(xAxisView)
        addSubview(yAxisView)
        addSubview(chartBaseView)
        
        setupObservable()
        setupSubViews()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        transformerProvider.setChartDimens(width: bounds.width - yAxisWidth, height: bounds.height - xAxisHeight)
        transformerProvider.prepareMatrixValuePx(dataRanges: transformerProvider.initDataRanges)
        
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
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setupSubViews() {
        xAxisView.transformerStream = transformerProvider.transformerStream
        xAxisView.transformerProvider = transformerProvider
        xAxisView.setup()
        
        yAxisView.transformerStream = transformerProvider.transformerStream
        yAxisView.transformerProvider = transformerProvider
        yAxisView.setup()
        
        chartBaseView.transformerStream = transformerProvider.transformerStream
        chartBaseView.transformerProvider = transformerProvider
    }
    
    public override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext()
        else {
            return
        }
        
        lineRender.drawSimpleLineChart(context: context, transformerProvider: transformerProvider)
    }
}
