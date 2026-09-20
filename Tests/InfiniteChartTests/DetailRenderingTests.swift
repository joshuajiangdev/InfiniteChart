import Combine
import CoreGraphics
import XCTest
@testable import InfiniteChart

final class DetailRenderingTests: XCTestCase {
    func testAllRenderersUseFiveAndFifteenMinuteSamplesIncludingTheLastSample() throws {
        for interval in [300_000.0, 900_000.0] {
            let data = IndexedRenderTestProvider(xValues: [0, interval, 2 * interval], nominalXStep: interval)
            let transformer = makeTransformer(range: 0...(2 * interval))
            try drawAll(data, transformer: transformer)

            XCTAssertEqual(data.candleRequests, data.xValues)
            XCTAssertEqual(data.volumeRequests, data.xValues)
            XCTAssertEqual(data.lineRequests, data.xValues)
        }
    }

    func testIrregularSamplePositionsAreNotRoundedOrReplacedWithOneMinuteSteps() throws {
        let data = IndexedRenderTestProvider(xValues: [60_500.25, 302_250.5, 946_100.75], nominalXStep: 300_000)
        try drawAll(data, transformer: makeTransformer(range: 0...1_000_000))

        XCTAssertEqual(data.candleRequests, data.xValues)
        XCTAssertEqual(data.volumeRequests, data.xValues)
        XCTAssertEqual(data.lineRequests, data.xValues)
    }

    func testRendererReadsTheNewIntervalWithoutBeingRecreated() throws {
        let data = IndexedRenderTestProvider(xValues: [0, 300_000, 600_000, 900_000], nominalXStep: 300_000)
        let renderer = CandleStickLineRender(dataProvider: data)
        let transformer = makeTransformer(range: 0...900_000)
        let context = try makeContext()
        renderer.drawCandleStickChart(context: context, transformerProvider: transformer)
        XCTAssertEqual(data.candleRequests, [0, 300_000, 600_000, 900_000])

        data.xValues = [0, 900_000]
        data.nominalXStep = 900_000
        data.candleRequests = []
        renderer.drawCandleStickChart(context: context, transformerProvider: transformer)
        XCTAssertEqual(data.candleRequests, [0, 900_000])
    }

    func testSamplesIncludeNeighborsForClippedBarsAndLineSegments() {
        let data = IndexedRenderTestProvider(xValues: [0, 300_000, 600_000, 900_000], nominalXStep: 300_000)
        let samples = ChartRenderSamples.xValues(dataProvider: data, transformerProvider: makeTransformer(range: 350_000...550_000))
        XCTAssertEqual(Array(samples), [300_000, 600_000])
    }

    func testCandleAndVolumeWidthsTrackIntervalAndLeaveMissingBucketsEmpty() throws {
        let data = IndexedRenderTestProvider(xValues: [300_000, 1_200_000], nominalXStep: 300_000)
        let transformer = makeTransformer(range: 0...12_000_000)
        let candleContext = try makeContext()
        CandleStickLineRender(dataProvider: data).drawCandleStickChart(context: candleContext, transformerProvider: transformer)
        let volumeContext = try makeContext()
        VolumeRender(dataProvider: data).drawVolumeChart(
            context: volumeContext, transformerProvider: transformer, rect: CGRect(x: 0, y: 0, width: 400, height: 200)
        )

        // Five minutes occupies ten points: eight points of body and two of gap.
        for context in [candleContext, volumeContext] {
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            XCTAssertGreaterThan(alpha(atX: 6, y: 50, pixels: pixels), 200)
            XCTAssertGreaterThan(alpha(atX: 13, y: 50, pixels: pixels), 200)
            XCTAssertEqual(alpha(atX: 5, y: 50, pixels: pixels), 0)
            XCTAssertEqual(alpha(atX: 14, y: 50, pixels: pixels), 0)
            XCTAssertEqual(alpha(atX: 20, y: 50, pixels: pixels), 0, "The missing ten-minute bucket stays empty.")
            XCTAssertEqual(alpha(atX: 30, y: 50, pixels: pixels), 0, "The missing fifteen-minute bucket stays empty.")
            XCTAssertGreaterThan(alpha(atX: 40, y: 50, pixels: pixels), 200, "The last available sample is rendered.")
        }

        data.nominalXStep = 900_000
        XCTAssertEqual(ChartRenderSamples.barWidth(dataProvider: data, transformerProvider: transformer, legacyWidth: 4), 24, accuracy: 0.001)
        let zoomedIn = makeTransformer(range: 0...1_200_000)
        XCTAssertEqual(ChartRenderSamples.barWidth(dataProvider: data, transformerProvider: zoomedIn, legacyWidth: 4), 24, "Widths are capped when zoomed far in.")
    }

    private func drawAll(_ data: IndexedRenderTestProvider, transformer: AccelerateTransformerProvider) throws {
        let context = try makeContext()
        CandleStickLineRender(dataProvider: data).drawCandleStickChart(context: context, transformerProvider: transformer)
        VolumeRender(dataProvider: data).drawVolumeChart(
            context: context, transformerProvider: transformer, rect: CGRect(x: 0, y: 0, width: 400, height: 200)
        )
        LineRender(dataProvider: data).drawSimpleLineChart(context: context, transformerProvider: transformer)
    }

    private func makeTransformer(range: ClosedRange<Double>) -> AccelerateTransformerProvider {
        AccelerateTransformerProvider(
            size: CGSize(width: 400, height: 200),
            dataRanges: DataRanges(chartXMin: range.lowerBound, deltaX: range.upperBound - range.lowerBound, chartYMin: 0, deltaY: 100)
        )
    }

    private func makeContext() throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 400 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func alpha(atX x: Int, y: Int, pixels: UnsafeMutablePointer<UInt8>) -> UInt8 {
        pixels[(y * 400 + x) * 4 + 3]
    }
}

private final class IndexedRenderTestProvider: IndexedChartDataProvider, CandleStickDataProvider, VolumeDataProvider, LineChartDataProvider {
    let redrawStream = Empty<Void, Never>().eraseToAnyPublisher()
    let tranformerUpdatedDelegate: ChartDataProviderDelegate? = nil
    let technicalIndicators: [TechnicalIndicator] = []
    var xValues: [Double]
    var nominalXStep: Double
    var candleRequests: [Double] = []
    var volumeRequests: [Double] = []
    var lineRequests: [Double] = []

    init(xValues: [Double], nominalXStep: Double) {
        self.xValues = xValues
        self.nominalXStep = nominalXStep
    }

    func getInitDataRanges() -> DataRanges? { nil }

    func getXValues(in range: ClosedRange<Double>) -> [Double] {
        xValues.filter { range.contains($0) }
    }

    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? {
        if seekBelow {
            return xValues.last { $0 <= xValue }
        }
        return xValues.first { $0 >= xValue }
    }

    func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint? {
        candleRequests.append(xValue)
        guard xValues.contains(xValue) else { return nil }
        return CandleStickDataPoint(high: 90, low: 10, open: 20, close: 80, color: .red)
    }

    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)? {
        volumeRequests.append(xValue)
        return xValues.contains(xValue) ? (100, .blue) : nil
    }

    func getYValue(for xValue: Double) -> Double? {
        lineRequests.append(xValue)
        return xValues.contains(xValue) ? 50 : nil
    }
}
