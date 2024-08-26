import UIKit
import Combine

public class InfiniteChartBase: UIView {
    
    var disposeBag = Set<AnyCancellable>()
    
    // MARK: - Private Properties
    
    let dataProvider: any ChartDataProviderBase
    
    let xAxisConfig: AxisConfig
    let yAxisConfig: AxisConfig

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
    
    lazy var lineRender: LineRender? = {
        guard let dataProvider = dataProvider as? LineChartDataProvider else {
            return nil
        }
        return LineRender(dataProvider: dataProvider)
    }()
    
    lazy var candleStickRender: CandleStickLineRender? = {
        guard let dataProvider = dataProvider as? CandleStickDataProvider else {
            return nil
        }
        return CandleStickLineRender(dataProvider: dataProvider)
    }()
    
    lazy var volumeRender: VolumeRender? = {
        guard let dataProvider = dataProvider as? VolumeDataProvider else {
            return nil
        }
        return VolumeRender(dataProvider: dataProvider)
    }()
    
    public init(
        frame: CGRect, 
        dataProvider: any ChartDataProviderBase, 
        xAxisConfig: AxisConfig = AxisConfig(), 
        yAxisConfig: AxisConfig = AxisConfig()
    ) {
        self.dataProvider = dataProvider
        self.xAxisConfig = xAxisConfig
        self.yAxisConfig = yAxisConfig
        
        super.init(frame: frame)
        
        backgroundColor = .clear

        addSubview(xAxisView)
        addSubview(yAxisView)
        addSubview(chartBaseView)
        
        setupObservable()
        setupSubViews()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        transformerProvider.setChartDimens(width: bounds.width - yAxisConfig.requiredSpace, height: bounds.height - xAxisConfig.requiredSpace)
        transformerProvider.prepareMatrixValuePx(dataRanges: transformerProvider.initDataRanges)
        
        xAxisView.frame = CGRect(
            x: 0,
            y: bounds.size.height - xAxisConfig.requiredSpace,
            width: bounds.size.width - yAxisConfig.requiredSpace,
            height: xAxisConfig.requiredSpace
        )
        
        yAxisView.frame = CGRect(
            x: bounds.size.width - yAxisConfig.requiredSpace,
            y: 0,
            width: yAxisConfig.requiredSpace,
            height: bounds.size.height - xAxisConfig.requiredSpace
        )
        
        chartBaseView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.size.width - yAxisConfig.requiredSpace,
            height: bounds.size.height - xAxisConfig.requiredSpace
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setupSubViews() {
        xAxisView.transformerStream = transformerProvider.transformerStream
        xAxisView.transformerProvider = transformerProvider
        xAxisView.config = xAxisConfig
        xAxisView.setup()
        
        yAxisView.transformerStream = transformerProvider.transformerStream
        yAxisView.transformerProvider = transformerProvider
        yAxisView.config = yAxisConfig
        yAxisView.setup()
        
        chartBaseView.transformerStream = transformerProvider.transformerStream
        chartBaseView.transformerProvider = transformerProvider
    }
    
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        
        let height = rect.height - xAxisConfig.requiredSpace
        let width = rect.width - yAxisConfig.requiredSpace
        
        let mainChartRect = CGRect(x: 0, y: 0, width: width, height: height * 2/3)
        let volumeChartRect = CGRect(x: 0, y: mainChartRect.maxY, width: width, height: height * 1/3)
        
        // Draw candlestick chart first (as background)
        candleStickRender?.drawCandleStickChart(context: context, transformerProvider: transformerProvider)
        
        // Draw line chart on top
//        lineRender?.drawSimpleLineChart(context: context, transformerProvider: transformerProvider)
        
        // Draw volume chart
        volumeRender?.drawVolumeChart(context: context, transformerProvider: transformerProvider, rect: volumeChartRect)
    }
}
