import UIKit
import Combine

public class InfiniteChartBase: UIView {
    
    let xAxisHeight: CGFloat = 50
    let yAxisWidth: CGFloat = 50

    var dataRanges: DataRanges?
    lazy var dataFetcher = BTCDataFetcher()
    var disposeBag = Set<AnyCancellable>()
    
    // TODO: Clear config/setup flow
    lazy var transformerProvider: AccelerateTransformerProvider = {
        guard let ranges = dataFetcher.getDataRanges() else {
            fatalError("Failed to get data ranges from BTCDataFetcher")
        }
        let dataRanges = DataRanges(
            chartXMin: ranges.minX,
            deltaX: ranges.deltaX,
            chartYMin: ranges.minY,
            deltaY: ranges.deltaY
        )
        
        self.dataRanges = dataRanges
        
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
    lazy var lineRender = LineRender(dataProvider: LineDataProvider(dataFetcher: dataFetcher))
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .red

        addSubview(xAxisView)
        addSubview(yAxisView)
        addSubview(chartBaseView)
        
        // Initialize data fetcher and wait for data to be available
        Task {
            await waitForDataFetcher()
            DispatchQueue.main.async { [weak self] in
                self?.setupViews()
            }
        }
    }

    private func waitForDataFetcher() async {
        while dataFetcher.getDataRanges() == nil {
            try? await Task.sleep(nanoseconds: 100_000_000) // Sleep for 0.1 seconds
        }
    }
    
    private func setupViews() {
        // Access transformerProvider here to trigger its initialization
        _ = transformerProvider
        setupObservable()
        setNeedsLayout()
        layoutIfNeeded()
        
        setNeedsDisplay()
        
        setup()
        
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let dataRanges else {
            return
        }
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
        fatalError("init(coder:) has not been implemented")
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
    
    public override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext(),
            let dataRanges
        else {
            return
        }
        
        lineRender.drawSimpleLineChart(context: context, transformerProvider: transformerProvider)
    }
}
