import Foundation
import CoreGraphics
import Combine

public class InfiniteChartBase: ChartPlatformView {

    /// Delivered on the main queue after navigation or layout changes. Data-only
    /// redraws do not trigger this callback. The application owns detail selection.
    public var onViewportChange: ((ChartViewportChange) -> Void)? {
        didSet {
            lastNotifiedViewport = nil
            scheduleViewportChange(reason: .initial)
        }
    }

    /// Nil until the first layout with a nonempty plot area.
    public var viewport: ChartViewport? {
        guard hasLaidOutChart else { return nil }
        let size = CGSize(width: transformerProvider.chartWidth, height: transformerProvider.chartHeight)
        let topLeft = transformerProvider.transformer.valueForTouchPoint(.zero)
        let bottomRight = transformerProvider.transformer.valueForTouchPoint(CGPoint(x: size.width, y: size.height))
        guard topLeft.x.isFinite, topLeft.y.isFinite, bottomRight.x.isFinite, bottomRight.y.isFinite,
              topLeft.x < bottomRight.x, bottomRight.y < topLeft.y else { return nil }
        return ChartViewport(visibleXRange: topLeft.x...bottomRight.x,
                             visibleYRange: bottomRight.y...topLeft.y, plotSize: size)
    }

    /// Optional positive, finite horizontal span limits in the provider's X units.
    /// Nil leaves the horizontal span unrestricted. Invalid limits are ignored.
    public var xSpanLimits: ClosedRange<Double>? {
        get { transformerProvider.xSpanLimits }
        set {
            if let limits = newValue {
                guard limits.lowerBound.isFinite, limits.lowerBound > 0,
                      limits.upperBound.isFinite else { return }
            }
            transformerProvider.xSpanLimits = newValue
        }
    }

    private var hasLaidOutChart = false
    private var lastNotifiedViewport: ChartViewport?
    private var pendingViewportReason: ChartViewportChange.Reason?
    
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
        transformerProvider.viewportChanges
            .sink { [weak self] reason in self?.scheduleViewportChange(reason: reason) }
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

    private func scheduleViewportChange(reason: ChartViewportChange.Reason) {
        let alreadyScheduled = pendingViewportReason != nil
        pendingViewportReason = reason
        guard !alreadyScheduled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let reason = self.pendingViewportReason else { return }
            self.pendingViewportReason = nil
            self.notifyViewportChange(reason: reason)
        }
    }

    private func notifyViewportChange(reason: ChartViewportChange.Reason) {
        guard let viewport, viewport != lastNotifiedViewport else { return }
        lastNotifiedViewport = viewport
        dataProvider.tranformerUpdatedDelegate?.transformerDidUpdate(transformer: transformerProvider.transformer)
        onViewportChange?(ChartViewportChange(viewport: viewport, reason: reason))
    }

    /// Navigates horizontally while retaining the current vertical range.
    /// Data updates through the provider's redraw stream preserve this viewport.
    public func setVisibleXRange(_ range: ClosedRange<Double>) {
        guard let viewport else { return }
        let requestedSpan = range.upperBound - range.lowerBound
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              requestedSpan.isFinite, requestedSpan > 0 else { return }
        let span = xSpanLimits.map { min(max(requestedSpan, $0.lowerBound), $0.upperBound) } ?? requestedSpan
        let center = range.lowerBound + requestedSpan / 2
        transformerProvider.prepareMatrixValuePx(dataRanges: DataRanges(
            chartXMin: center - span / 2, deltaX: span,
            chartYMin: viewport.visibleYRange.lowerBound,
            deltaY: viewport.visibleYRange.upperBound - viewport.visibleYRange.lowerBound
        ))
    }

    /// Fits the vertical range while preserving horizontal navigation exactly.
    /// The application can call this after replacing data without resetting zoom.
    /// Empty or nonfinite ranges are ignored, as are calls before the first layout.
    public func setVisibleYRange(_ range: ClosedRange<Double>) {
        guard viewport != nil else { return }
        transformerProvider.setVisibleYRange(range)
    }

    /// Explicitly returns to the provider's initial range. Replacing data alone
    /// never calls this method, so a detail-level transition does not move the plot.
    public func resetViewport() {
        guard hasLaidOutChart, let ranges = dataProvider.getInitDataRanges() else { return }
        transformerProvider.prepareMatrixValuePx(dataRanges: ranges)
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
            let previousViewport = viewport
            transformerProvider.setChartDimens(width: plotWidth, height: plotHeight)
            hasLaidOutChart = true
            transformerProvider.prepareMatrixValuePx(
                dataRanges: previousViewport?.dataRanges ?? transformerProvider.initDataRanges,
                reason: previousViewport == nil ? .initial : .resize
            )
            // Plot dimensions are part of the viewport even if the transform
            // happens to remain identical (for example, the first tiny layout).
            scheduleViewportChange(reason: previousViewport == nil ? .initial : .resize)
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
