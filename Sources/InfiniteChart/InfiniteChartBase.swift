import Foundation
import CoreGraphics
import Combine

public class InfiniteChartBase: ChartPlatformView {

    /// Delivered asynchronously on the main actor after navigation or layout changes.
    /// Rapid changes coalesce to the latest viewport; data-only redraws do not notify.
    public var onViewportChange: ((ChartViewport) -> Void)? {
        didSet {
            lastNotifiedViewport = nil
            scheduleViewportChange()
        }
    }

    /// Nil before the first layout or while the plot area is empty.
    public var viewport: ChartViewport? {
        guard hasLaidOutChart, chartBaseView.bounds.width > 0, chartBaseView.bounds.height > 0 else { return nil }
        return transformerProvider.viewport
    }

    private var hasLaidOutChart = false
    private var lastNotifiedViewport: ChartViewport?
    private var isViewportNotificationScheduled = false
    
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
            // Constraint-based layouts commonly create the view at zero size.
            // Keep the initial transform invertible until the first real layout.
            size: CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1)),
            dataRanges: dataRanges
        )
    }()
    
    private func setupObservable() {
        transformerProvider.transformerStream
            .sink { [weak self] _ in self?.scheduleViewportChange() }
            .store(in: &disposeBag)
        Publishers.CombineLatest(
            transformerProvider.$transformer,
            dataProvider.redrawStream
        )
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] _, _ in
            self?.requestChartDisplay()
        }).store(in: &disposeBag)
    }
    
    private func scheduleViewportChange() {
        guard !isViewportNotificationScheduled else { return }
        isViewportNotificationScheduled = true
        // @Published emits before its stored value changes. Read the snapshot
        // after the update finishes, coalescing synchronous changes into one callback.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isViewportNotificationScheduled = false
            guard let viewport = self.viewport, viewport != self.lastNotifiedViewport else { return }
            self.lastNotifiedViewport = viewport
            self.onViewportChange?(viewport)
        }
    }

    lazy var xAxisView = XAxisView(frame: .zero)
    lazy var yAxisView = YAxisView(frame: .zero)
    lazy var chartBaseView = ChartBaseView(frame: .zero)
    
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
    
    lazy var technicalIndicatorRender: TechnicalIndicatorRender = {
        return TechnicalIndicatorRender(dataProvider: dataProvider)
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
        
        configureChartAppearance(background: .clear)

        addSubview(xAxisView)
        addSubview(yAxisView)
        addSubview(chartBaseView)
        
        setupObservable()
        setupSubViews()
    }

    public override func layoutChartSubviews() {
        super.layoutChartSubviews()

        let plotWidth = max(0, bounds.width - yAxisConfig.requiredSpace)
        let plotHeight = max(0, bounds.height - xAxisConfig.requiredSpace)
        
        xAxisView.frame = CGRect(
            x: 0,
            y: plotHeight,
            width: plotWidth,
            height: xAxisConfig.requiredSpace
        )
        
        yAxisView.frame = CGRect(
            x: plotWidth,
            y: 0,
            width: yAxisConfig.requiredSpace,
            height: plotHeight
        )
        
        chartBaseView.frame = CGRect(
            x: 0,
            y: 0,
            width: plotWidth,
            height: plotHeight
        )

        if plotWidth > 0, plotHeight > 0,
           !hasLaidOutChart || plotWidth != transformerProvider.chartWidth || plotHeight != transformerProvider.chartHeight {
            transformerProvider.setChartDimens(width: plotWidth, height: plotHeight)
            hasLaidOutChart = true
            transformerProvider.prepareMatrixValuePx(dataRanges: transformerProvider.initDataRanges)
            // Size and first layout matter even when the transform is unchanged.
            scheduleViewportChange()
        }
        requestChartDisplay()
    }
    
    public required init?(coder: NSCoder) {
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
        guard let context = currentChartGraphicsContext() else {
            return
        }
        
        // AppKit can request only a dirty subregion; chart geometry uses the full bounds.
        let height = bounds.height - xAxisConfig.requiredSpace
        let width = bounds.width - yAxisConfig.requiredSpace
        guard width > 0, height > 0 else { return }
        
        let mainChartRect = CGRect(x: 0, y: 0, width: width, height: height * 2/3)
        let volumeChartRect = CGRect(x: 0, y: mainChartRect.maxY, width: width, height: height * 1/3)
        
        // Draw candlestick chart first (as background)
        candleStickRender?.drawCandleStickChart(context: context, transformerProvider: transformerProvider)
        
        // Draw line chart on top
//        lineRender?.drawSimpleLineChart(context: context, transformerProvider: transformerProvider)
        
        // Draw volume chart
        volumeRender?.drawVolumeChart(context: context, transformerProvider: transformerProvider, rect: volumeChartRect)
        
        // Draw technical indicators
        technicalIndicatorRender.drawTechnicalIndicators(context: context, transformerProvider: transformerProvider)
    }
}

final class TechnicalIndicatorRender {
    let dataProvider: any ChartDataProviderBase
    
    init(dataProvider: any ChartDataProviderBase) {
        self.dataProvider = dataProvider
    }
    
    func drawTechnicalIndicators(context: CGContext, transformerProvider: AccelerateTransformerProvider) {
        let transformer = transformerProvider.transformer
        
        for indicator in dataProvider.technicalIndicators {
            let linePath = CGMutablePath()
            var isFirstPoint = true
            
            for point in indicator.dataPoints {
                let pixelPoint = transformer.pixelForValue(DoublePrecisionPoint(x: point.x, y: point.y))
                
                if isFirstPoint {
                    linePath.move(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y))
                    isFirstPoint = false
                } else {
                    linePath.addLine(to: CGPoint(x: pixelPoint.x, y: pixelPoint.y))
                }
            }
            
            context.saveGState()
            defer { context.restoreGState() }
            
            context.addPath(linePath)
            context.setStrokeColor(indicator.color.cgColor)
            context.setLineWidth(2.0)
            context.strokePath()
        }
    }
}
