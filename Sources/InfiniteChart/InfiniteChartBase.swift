import Foundation
import CoreGraphics
import Combine

public class InfiniteChartBase: ChartPlatformView {

    /// The current viewport, or nil before layout or while the plot is empty.
    /// Read `value` for a snapshot or subscribe for changes on the main actor.
    /// Defer chart mutations from subscribers until the transform update completes.
    public let viewportStream = CurrentValueSubject<ChartViewport?, Never>(nil)

    private var hasLaidOutChart = false
    
    var disposeBag = Set<AnyCancellable>()
    
    // MARK: - Private Properties
    
    let dataProvider: any ChartDataProviderBase
    
    let xAxisConfig: AxisConfig
    let yAxisConfig: AxisConfig

    lazy var transformerProvider: AffineTransformerProvider = {
        let dataRanges = dataProvider.getInitDataRanges()
            ?? DataRanges(chartXMin: 0, deltaX: 0, chartYMin: 0, deltaY: 0)
        
        return AffineTransformerProvider(
            // Constraint-based layouts commonly create the view at zero size.
            // Keep the initial transform invertible until the first real layout.
            size: CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1)),
            dataRanges: dataRanges
        )
    }()
    
    private func updateViewport() {
        let viewport = hasLaidOutChart && !chartBaseView.bounds.isEmpty
            ? transformerProvider.viewport
            : nil
        guard viewport != viewportStream.value else { return }
        viewportStream.send(viewport)
    }

    /// Publishes viewport changes synchronously and schedules transform/data redraws on the main queue.
    /// Initial provider ranges are adopted on redraw only while no valid ranges have been installed.
    private func setupObservable() {
        transformerProvider.transformerStream
            .sink { [weak self] _ in
                self?.updateViewport()
            }
            .store(in: &disposeBag)
        Publishers.Merge(
            transformerProvider.transformerStream.map { _ in () }.eraseToAnyPublisher(),
            dataProvider.redrawStream
        )
        .receive(on: DispatchQueue.main)
        .sink(receiveValue: { [weak self] in
            guard let self else { return }
            if !self.transformerProvider.hasValidDataRanges,
               let ranges = self.dataProvider.getInitDataRanges() {
                self.transformerProvider.prepareMatrixValuePx(dataRanges: ranges)
            }
            self.requestChartDisplay()
        }).store(in: &disposeBag)
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

    /// Creates a chart and axes backed by the provider's supported drawing protocols.
    /// A provider without valid initial ranges can supply them later through its redraw stream.
    ///
    /// - Parameters:
    ///   - frame: Initial view frame in points; zero-sized views can be laid out later.
    ///   - dataProvider: The retained source of samples, initial ranges, and redraw events.
    ///   - xAxisConfig: Styling, label formatting, and space reserved for the horizontal axis.
    ///   - yAxisConfig: Styling, label formatting, and space reserved for the vertical axis.
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

    /// Lays out the axes and plot, preserving visible data ranges when the plot resizes.
    /// Updates the viewport after layout, including transitions to or from an empty plot.
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
            hasLaidOutChart = true
            transformerProvider.setChartDimens(width: plotWidth, height: plotHeight)
        }
        // Layout can make the viewport available without changing the transform.
        updateViewport()
        requestChartDisplay()
    }
    
    /// Unsupported: construct charts with a data provider instead of decoding them from an archive.
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Connects axis configuration and transform observation, and assigns the plot's gesture provider.
    public func setupSubViews() {
        xAxisView.transformerStream = transformerProvider.transformerStream
        xAxisView.transformerProvider = transformerProvider
        xAxisView.config = xAxisConfig
        xAxisView.setup()
        
        yAxisView.transformerStream = transformerProvider.transformerStream
        yAxisView.transformerProvider = transformerProvider
        yAxisView.config = yAxisConfig
        yAxisView.setup()
        
        chartBaseView.transformerProvider = transformerProvider
    }
    
    /// Draws candles, volume, and indicators using full plot geometry, even for a partial redraw.
    /// Skips drawing until the plot has positive dimensions and valid initial data ranges.
    public override func draw(_ rect: CGRect) {
        guard let context = currentChartGraphicsContext() else {
            return
        }
        
        // AppKit can request only a dirty subregion; chart geometry uses the full bounds.
        let height = bounds.height - xAxisConfig.requiredSpace
        let width = bounds.width - yAxisConfig.requiredSpace
        guard width > 0, height > 0, transformerProvider.hasValidDataRanges else { return }
        
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
