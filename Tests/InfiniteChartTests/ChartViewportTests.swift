import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import InfiniteChart

final class ChartViewportTests: XCTestCase {
    @MainActor
    func testInitialViewportWaitsForNonemptyLayoutAndReportsDataRangesAndPlotSize() async throws {
        let chart = makeChart(frame: .zero)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = {
            XCTAssertTrue(Thread.isMainThread)
            changes.append($0)
        }

        XCTAssertNil(chart.viewport)
        layout(chart)
        await drainMainQueue()
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(changes.isEmpty)

        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .initial)
        try assertViewport(changes.first?.viewport, x: 0...1_000, y: 0...100,
                           size: CGSize(width: 400, height: 300))
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    @MainActor
    func testViewportBecomesUnavailableWhenEitherPlotDimensionBecomesEmpty() async throws {
        for emptyFrame in [
            CGRect(x: 0, y: 0, width: 40, height: 330),
            CGRect(x: 0, y: 0, width: 440, height: 30)
        ] {
            let chart = makeChart()
            layout(chart)
            var changes: [ChartViewportChange] = []
            chart.onViewportChange = { changes.append($0) }
            await drainMainQueue()
            XCTAssertNotNil(chart.viewport)
            changes.removeAll()

            chart.frame = emptyFrame
            layout(chart)
            XCTAssertNil(chart.viewport)
            await drainMainQueue()

            XCTAssertNil(chart.viewport)
            XCTAssertTrue(changes.isEmpty, "An empty plot must not deliver a stale viewport.")

            chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
            layout(chart)
            await drainMainQueue()
            try assertViewport(chart.viewport, x: 0...1_000, y: 0...100)
        }
    }

    @MainActor
    func testZoomAndPanReportVisibleDataCoordinatesAndReasons() async throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last?.reason, .zoom)
        try assertViewport(changes.last?.viewport, x: 250...750, y: 25...75)

        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await drainMainQueue()

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.last?.reason, .pan)
        try assertViewport(changes.last?.viewport, x: 200...700, y: 30...80)
        XCTAssertEqual(chart.viewport, changes.last?.viewport)
    }

    @MainActor
    func testResizeReportsNewPlotSizeAndCurrentVisibleDataRanges() async throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await drainMainQueue()
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
        changes.removeAll()

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .resize)
        let transformer = chart.transformerProvider.transformer
        let topLeft = transformer.valueForTouchPoint(.zero)
        let bottomRight = transformer.valueForTouchPoint(CGPoint(x: 800, y: 500))
        try assertViewport(changes.first?.viewport,
                           x: topLeft.x...bottomRight.x, y: bottomRight.y...topLeft.y,
                           size: CGSize(width: 800, height: 500))
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    @MainActor
    func testCallbackAttachedAfterNavigationReceivesCurrentViewport() async throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await drainMainQueue()

        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .initial)
        try assertViewport(changes.first?.viewport, x: 200...700, y: 30...80)
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    @MainActor
    func testRapidNavigationCoalescesToLatestViewportAndReason() async throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 0))
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .pan)
        try assertViewport(changes.first?.viewport, x: 150...650, y: 30...80)
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    @MainActor
    func testProviderRedrawInsideViewportCallbackDoesNotCauseFeedbackOrMoveChart() async throws {
        let provider = ViewportTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { change in
            changes.append(change)
            // An application can replace displayed data in response to navigation.
            provider.redraw.send(())
        }
        await drainMainQueue()
        XCTAssertEqual(changes.count, 1)
        changes.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .zoom)
        try assertViewport(chart.viewport, x: 250...750, y: 0...100)
        let navigatedViewport = chart.viewport

        provider.redraw.send(())
        provider.redraw.send(())
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(chart.viewport, navigatedViewport)
    }

    @MainActor
    func testUnchangedLayoutAndNavigationDoNotRepeatNotification() async throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()
        let originalViewport = chart.viewport

        layout(chart)
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 1, scaleY: 1, x: 173, y: 91)
        chart.transformerProvider.translate(delta: .zero)
        await drainMainQueue()

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(chart.viewport, originalViewport)
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
    }

    @MainActor
    func testExistingRangePreparationReportsProgrammaticChange() async throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        await drainMainQueue()
        changes.removeAll()

        chart.transformerProvider.prepareMatrixValuePx(
            dataRanges: DataRanges(chartXMin: 500, deltaX: 200, chartYMin: -20, deltaY: 40)
        )
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .programmatic)
        try assertViewport(changes.first?.viewport, x: 500...700, y: -20...20)
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    @MainActor
    func testFirstOnePointPlotReportsInitialViewportEvenWithUnchangedTransform() async throws {
        let chart = makeChart(frame: .zero)
        var changes: [ChartViewportChange] = []
        chart.onViewportChange = { changes.append($0) }
        layout(chart)
        await drainMainQueue()
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(changes.isEmpty)

        // The initial zero-sized view already uses a one-point transform.
        // Its first real layout must still make the viewport observable.
        chart.frame = CGRect(x: 0, y: 0, width: 41, height: 31)
        layout(chart)
        await drainMainQueue()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .initial)
        try assertViewport(changes.first?.viewport, x: 0...1_000, y: 0...100,
                           size: CGSize(width: 1, height: 1))
        XCTAssertEqual(chart.viewport, changes.first?.viewport)
    }

    private func assertViewport(
        _ viewport: ChartViewport?,
        x: ClosedRange<Double>,
        y: ClosedRange<Double>,
        size: CGSize = CGSize(width: 400, height: 300),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let viewport = try XCTUnwrap(viewport, file: file, line: line)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, x.lowerBound, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(viewport.visibleXRange.upperBound, x.upperBound, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(viewport.visibleYRange.lowerBound, y.lowerBound, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(viewport.visibleYRange.upperBound, y.upperBound, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(viewport.plotSize, size, file: file, line: line)
    }

    @MainActor
    private func makeChart(
        frame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 330),
        provider: ViewportTestProvider = ViewportTestProvider()
    ) -> InfiniteChartBase {
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
