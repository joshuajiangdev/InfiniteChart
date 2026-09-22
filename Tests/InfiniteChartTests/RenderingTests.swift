import Combine
import CoreGraphics
import XCTest
@testable import InfiniteChart

final class RenderingTests: XCTestCase {
    /// Checks that traversal preserves fractional sample coordinates and includes plot-boundary neighbors.
    func testProviderTraversalUsesIrregularFractionalCoordinatesAndBoundaryNeighbors() {
        let provider = RenderingTestDataProvider(xValues: [-0.25, 0.125, 0.5, 1.75, 3.25, 4.5])
        XCTAssertEqual(provider.renderingXValues(in: 0...4), provider.xValues)
        XCTAssertEqual(provider.renderingXValues(in: 0.125...3.25), [0.125, 0.5, 1.75, 3.25])
        XCTAssertEqual(provider.renderingXValues(in: -2 ... -1), [-0.25])
        XCTAssertEqual(provider.renderingXValues(in: 5...6), [4.5])
        XCTAssertEqual(RenderingTestDataProvider(xValues: []).renderingXValues(in: 0...4), [])
    }

    /// Checks that malformed neighbor results terminate traversal without repeating or appending invalid samples.
    func testProviderTraversalStopsOnInvalidOrNonAdvancingCoordinates() {
        let provider = RenderingTestDataProvider(xValues: [0, 1])
        for invalidNext in [0, -1, Double.nan, Double.infinity] {
            provider.nextOverride = invalidNext
            XCTAssertEqual(provider.renderingXValues(in: 0...4), [0])
        }
        provider.xValues = [.nan]
        XCTAssertEqual(provider.renderingXValues(in: 0...4), [])
    }

    /// Verifies each renderer draws provider-defined samples and volume samples are fetched once per draw.
    func testAllRenderersVisitEveryIrregularSample() throws {
        let provider = RenderingTestDataProvider(xValues: [0.125, 0.5, 1.75, 3.25])
        let transformer = makeTransformer()
        let line = try makeContext()
        LineRender(dataProvider: provider).drawSimpleLineChart(context: line, transformerProvider: transformer)
        XCTAssertEqual(provider.lineRequests, provider.xValues)
        XCTAssertTrue(try hasOpaquePixels(line))

        let candle = try makeContext()
        CandleStickLineRender(dataProvider: provider).drawCandleStickChart(context: candle, transformerProvider: transformer)
        XCTAssertEqual(provider.candleRequests, provider.xValues)
        XCTAssertTrue(try hasOpaquePixels(candle))

        let volume = try makeContext()
        VolumeRender(dataProvider: provider).drawVolumeChart(context: volume, transformerProvider: transformer,
                                                          rect: CGRect(x: 0, y: 0, width: 160, height: 100))
        XCTAssertEqual(provider.volumeRequests, provider.xValues, "Each volume sample is fetched once per draw.")
        XCTAssertTrue(try hasOpaquePixels(volume))
    }

    /// Verifies nonfinite line values leave a visible gap between otherwise valid segments.
    func testInvalidLineSamplesBreakThePath() throws {
        let provider = RenderingTestDataProvider(xValues: [0.5, 1, 2, 3, 3.5])
        for missingValue in [Double.nan, Double.infinity] {
            provider.lineValues = [2: missingValue]
            let context = try makeContext()
            LineRender(dataProvider: provider).drawSimpleLineChart(context: context, transformerProvider: makeTransformer())
            XCTAssertTrue(try hasOpaquePixels(context, x: 30))
            XCTAssertFalse(try hasOpaquePixels(context, x: 80), "Invalid samples must not connect the neighboring line segments.")
            XCTAssertTrue(try hasOpaquePixels(context, x: 130))
        }
    }

    /// Verifies that only visible, positive, finite volumes set the panel scale and produce bars.
    func testInvalidAndOffscreenVolumesDoNotHideVisibleBars() throws {
        let provider = RenderingTestDataProvider(xValues: [-1, 0.5, 1, 2, 3, 3.5, 5])
        provider.volumeValues = [-1: 1_000, 0.5: .nan, 1: -.infinity, 2: -10, 3: .infinity, 3.5: 10, 5: 1_000]
        let context = try makeContext()
        VolumeRender(dataProvider: provider).drawVolumeChart(context: context, transformerProvider: makeTransformer(),
                                                          rect: CGRect(x: 0, y: 0, width: 160, height: 100))
        XCTAssertTrue(try hasOpaquePixels(context, x: 140, y: 50), "The valid visible volume should occupy the full panel height.")
        for x in [20, 40, 80, 120] {
            XCTAssertFalse(try hasOpaquePixels(context, x: x))
        }
        XCTAssertFalse(provider.volumeRequests.contains(-1))
        XCTAssertFalse(provider.volumeRequests.contains(5))
    }

    /// Verifies a candle with equal OHLC values stays visible while nonfinite candles draw no pixels.
    func testFlatCandlesHaveAVisibleBodyAndInvalidCandlesAreSkipped() throws {
        let provider = RenderingTestDataProvider(xValues: [1, 2, 3])
        provider.candleValues = [
            1: CandleStickDataPoint(high: .nan, low: 2, open: 3, close: 7, color: .red),
            2: CandleStickDataPoint(high: 5, low: 5, open: 5, close: 5, color: .red),
            3: CandleStickDataPoint(high: 9, low: 2, open: .infinity, close: 7, color: .red)
        ]
        let context = try makeContext()
        CandleStickLineRender(dataProvider: provider).drawCandleStickChart(context: context, transformerProvider: makeTransformer())
        XCTAssertTrue(try hasOpaquePixels(context, x: 79))
        XCTAssertFalse(try hasOpaquePixels(context, x: 40))
        XCTAssertFalse(try hasOpaquePixels(context, x: 120))
    }

    private func makeTransformer() -> AffineTransformerProvider {
        AffineTransformerProvider(size: CGSize(width: 160, height: 100),
                                      dataRanges: DataRanges(chartXMin: 0, deltaX: 4, chartYMin: 0, deltaY: 10))
    }

    private func makeContext() throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 640,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    /// Scans an RGBA bitmap, optionally restricted to one row or column, for alpha above 100.
    private func hasOpaquePixels(_ context: CGContext, x: Int? = nil, y: Int? = nil) throws -> Bool {
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for row in y.map({ [$0] }) ?? Array(0..<context.height) {
            for column in x.map({ [$0] }) ?? Array(0..<context.width) {
                if pixels[row * context.bytesPerRow + column * 4 + 3] > 100 { return true }
            }
        }
        return false
    }
}

private final class RenderingTestDataProvider: LineChartDataProvider, CandleStickDataProvider, VolumeDataProvider {
    let redrawStream = Just(()).eraseToAnyPublisher()
    var xValues: [Double]
    var nextOverride: Double?
    var lineValues: [Double: Double] = [:]
    var volumeValues: [Double: Double] = [:]
    var candleValues: [Double: CandleStickDataPoint] = [:]
    var lineRequests: [Double] = []
    var candleRequests: [Double] = []
    var volumeRequests: [Double] = []

    init(xValues: [Double]) { self.xValues = xValues }

    func getInitDataRanges() -> DataRanges? { nil }

    /// Resolves clamped test neighbors, optionally injecting a malformed forward step to test termination.
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? {
        guard !xValues.isEmpty else { return nil }
        if !seekBelow, offset > 0, let nextOverride { return nextOverride }
        let index = seekBelow
            ? xValues.lastIndex(where: { $0 <= xValue }) ?? 0
            : xValues.firstIndex(where: { $0 >= xValue }) ?? xValues.count - 1
        return xValues[min(xValues.count - 1, max(0, index + (seekBelow ? -offset : offset)))]
    }

    func getYValue(for xValue: Double) -> Double? {
        lineRequests.append(xValue)
        return lineValues[xValue] ?? 5
    }

    func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint? {
        candleRequests.append(xValue)
        return candleValues[xValue] ?? CandleStickDataPoint(high: 9, low: 2, open: 3, close: 7, color: .red)
    }

    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)? {
        volumeRequests.append(xValue)
        return (volumeValues[xValue] ?? 5, .blue)
    }
}
