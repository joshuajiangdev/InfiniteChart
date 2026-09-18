import Combine
import XCTest
@testable import InfiniteChart

final class ChartViewportTests: XCTestCase {
    @MainActor
    func testInitialLayoutReportsDataRangeAndPlotSize() async throws {
        let chart = makeChart(frame: .zero)
        XCTAssertNil(chart.viewport)
        let ready = expectation(description: "Initial viewport")
        chart.onViewportChange = { change in
            XCTAssertEqual(change.reason, .initial)
            XCTAssertEqual(change.viewport.plotSize, CGSize(width: 400, height: 300))
            XCTAssertEqual(change.viewport.visibleXRange.lowerBound, 0, accuracy: 0.0001)
            XCTAssertEqual(change.viewport.visibleXRange.upperBound, 1_000, accuracy: 0.0001)
            ready.fulfill()
        }
        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        await fulfillment(of: [ready], timeout: 2)
    }

    @MainActor
    func testNavigationAndResizeReportReasonsWithoutLosingVisibleRange() async throws {
        let chart = makeChart()
        layout(chart)
        await drainMainQueue()
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
        await drainMainQueue()
        XCTAssertEqual(changes.last?.reason, .zoom)
        chart.transformerProvider.translate(delta: CGPoint(x: 20, y: 0))
        await drainMainQueue()
        XCTAssertEqual(changes.last?.reason, .pan)
        let beforeResize = try XCTUnwrap(chart.viewport)

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)
        await drainMainQueue()
        let afterResize = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(changes.last?.reason, .resize)
        XCTAssertEqual(afterResize.plotSize, CGSize(width: 800, height: 500))
        XCTAssertEqual(afterResize.visibleXRange.lowerBound, beforeResize.visibleXRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleXRange.upperBound, beforeResize.visibleXRange.upperBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleYRange.lowerBound, beforeResize.visibleYRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleYRange.upperBound, beforeResize.visibleYRange.upperBound, accuracy: 0.0001)
    }

    @MainActor
    func testApplicationDataRedrawDoesNotResetViewportOrCauseFeedback() async throws {
        let provider = ViewportTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { change in
            changes.append(change)
            // Equivalent to the app replacing its resolution on a viewport event.
            provider.redraw.send(())
        }
        await drainMainQueue()
        changes.removeAll()
        chart.setVisibleXRange(200...700)
        await drainMainQueue()
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .programmatic)
        let selectedViewport = try XCTUnwrap(chart.viewport)
        provider.redraw.send(())
        await drainMainQueue()
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(chart.viewport, selectedViewport)
        chart.resetViewport()
        await drainMainQueue()
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(try XCTUnwrap(chart.viewport).visibleXRange.upperBound, 1_000, accuracy: 0.0001)
    }

    @MainActor
    func testVerticalFitPreservesHorizontalNavigationAndReportsOneProgrammaticChange() async throws {
        let provider = ViewportTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        chart.setVisibleXRange(1_724_587_201_234...1_724_590_801_789)
        chart.transformerProvider.zoom(scaleX: 1.37, scaleY: 1, x: 173, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 17.3, y: 0))
        let originalXRange = try XCTUnwrap(chart.viewport).visibleXRange
        // Setting horizontal limits must not make a subsequent Y-only fit move X.
        chart.xSpanLimits = 60_000...120_000
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { change in
            changes.append(change)
            provider.redraw.send(())
        }
        await drainMainQueue()
        changes.removeAll()

        chart.setVisibleYRange(50_000...75_000)
        await drainMainQueue()
        let fittedViewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(fittedViewport.visibleXRange, originalXRange, "A vertical fit must leave horizontal navigation exactly unchanged.")
        XCTAssertEqual(fittedViewport.visibleYRange.lowerBound, 50_000, accuracy: 0.0001)
        XCTAssertEqual(fittedViewport.visibleYRange.upperBound, 75_000, accuracy: 0.0001)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .programmatic)
        XCTAssertEqual(changes.first?.viewport, fittedViewport)

        provider.redraw.send(())
        await drainMainQueue()
        XCTAssertEqual(changes.count, 1, "Replacing data must not repeat the viewport callback.")
        XCTAssertEqual(chart.viewport, fittedViewport, "A data redraw must retain both fitted ranges.")
    }

    @MainActor
    func testInvalidVerticalRangesAreIgnoredWithoutNotifying() async throws {
        let chart = makeChart(frame: .zero)
        chart.setVisibleYRange(10...20)
        XCTAssertNil(chart.viewport)
        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        // Negative values are valid; only the span must be positive.
        chart.setVisibleYRange(-200 ... -50)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()
        let original = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(original.visibleYRange.lowerBound, -200, accuracy: 0.0001)
        XCTAssertEqual(original.visibleYRange.upperBound, -50, accuracy: 0.0001)

        chart.setVisibleYRange(1...1)
        chart.setVisibleYRange(0...Double.infinity)
        chart.setVisibleYRange(-Double.infinity...0)
        chart.setVisibleYRange(-Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
        await drainMainQueue()
        XCTAssertEqual(chart.viewport, original)
        XCTAssertTrue(changes.isEmpty)
    }

    @MainActor
    func testRapidNavigationCoalescesToLatestViewport() async throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()
        chart.setVisibleXRange(100...900)
        chart.setVisibleXRange(300...700)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 0))
        await drainMainQueue()
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .pan)
        XCTAssertEqual(changes.first?.viewport, chart.viewport)
    }

    @MainActor
    func testSpanLimitsUseProviderUnitsAndPreserveZoomAnchor() throws {
        let chart = makeChart()
        layout(chart)
        chart.xSpanLimits = 200...2_000
        chart.transformerProvider.zoom(scaleX: 0.01, scaleY: 1, x: 200, y: 150)
        var viewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound, 2_000, accuracy: 0.0001)
        XCTAssertEqual((viewport.visibleXRange.lowerBound + viewport.visibleXRange.upperBound) / 2, 500, accuracy: 0.0001)
        chart.setVisibleXRange(490...510)
        viewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 400, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 600, accuracy: 0.0001)

        chart.xSpanLimits = nil
        chart.setVisibleXRange(0...(24 * 60 * 60_000))
        chart.transformerProvider.zoom(scaleX: 0.5, scaleY: 1)
        viewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound, 48 * 60 * 60_000, accuracy: 0.001)
    }

    @MainActor
    func testVerticalOnlyZoomPreservesXRangeAfterSpanLimitsChange() async throws {
        for limits in [200.0...400.0, 2_000.0...4_000.0] {
            for scaleY in [0.5, 1.0, 2.0] {
                let chart = makeChart()
                layout(chart)
                let original = try XCTUnwrap(chart.viewport)
                // Both a lower maximum and a higher minimum exclude the current X span.
                chart.xSpanLimits = limits
                var changes: [ChartViewportChange] = []
                chart.onViewportChange = { changes.append($0) }
                await drainMainQueue()
                changes.removeAll()

                chart.transformerProvider.zoom(scaleX: 1, scaleY: scaleY, x: 0, y: 150)
                await drainMainQueue()

                let zoomed = try XCTUnwrap(chart.viewport)
                XCTAssertEqual(zoomed.visibleXRange, original.visibleXRange)
                XCTAssertEqual(zoomed.visibleYRange.lowerBound, 50 - 50 / scaleY, accuracy: 0.0001)
                XCTAssertEqual(zoomed.visibleYRange.upperBound, 50 + 50 / scaleY, accuracy: 0.0001)
                if scaleY == 1 {
                    XCTAssertTrue(changes.isEmpty, "An unchanged gesture must not move the viewport.")
                } else {
                    XCTAssertEqual(changes.count, 1)
                    XCTAssertEqual(changes.first?.reason, .zoom)
                    XCTAssertEqual(changes.first?.viewport, zoomed)
                }
            }
        }
    }

    @MainActor
    func testInitialLayoutAndResetRespectSpanLimits() throws {
        let chart = makeChart()
        chart.xSpanLimits = 200...400
        layout(chart)
        var viewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 300, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 700, accuracy: 0.0001)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 10, y: 10))
        chart.resetViewport()
        viewport = try XCTUnwrap(chart.viewport)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 300, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 700, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleYRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleYRange.upperBound, 100, accuracy: 0.0001)
    }

    @MainActor
    func testInvalidNavigationDoesNotCorruptViewport() throws {
        let chart = makeChart()
        layout(chart)
        let original = try XCTUnwrap(chart.viewport)
        chart.setVisibleXRange(1...1)
        chart.setVisibleXRange(0...Double.infinity)
        chart.transformerProvider.zoom(scaleX: 0, scaleY: 1)
        chart.transformerProvider.zoom(scaleX: .infinity, scaleY: 1)
        chart.transformerProvider.translate(delta: CGPoint(x: CGFloat.nan, y: 0))
        XCTAssertEqual(chart.viewport, original)
    }

    @MainActor
    private func makeChart(frame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 330),
                           provider: ViewportTestProvider = ViewportTestProvider()) -> InfiniteChartBase {
        InfiniteChartBase(frame: frame, dataProvider: provider,
                          xAxisConfig: AxisConfig(requiredSpace: 30),
                          yAxisConfig: AxisConfig(requiredSpace: 40))
    }

    @MainActor
    private func layout(_ chart: InfiniteChartBase) {
        #if canImport(UIKit)
        chart.layoutSubviews()
        #else
        chart.layout()
        #endif
    }

    @MainActor
    private func drainMainQueue() async {
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

private final class ViewportTestProvider: ChartDataProviderBase {
    let redraw = CurrentValueSubject<Void, Never>(())
    var redrawStream: AnyPublisher<Void, Never> { redraw.eraseToAnyPublisher() }
    weak var tranformerUpdatedDelegate: (any ChartDataProviderDelegate)?
    var technicalIndicators: [TechnicalIndicator] { [] }
    func getInitDataRanges() -> DataRanges? {
        DataRanges(chartXMin: 0, deltaX: 1_000, chartYMin: 0, deltaY: 100)
    }
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? { nil }
}
