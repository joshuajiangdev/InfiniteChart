import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import InfiniteChart

final class ChartViewportTests: XCTestCase {
    @MainActor
    func testInitialViewportWaitsForNonemptyLayoutAndReportsDataRangesAndPlotSize() async throws {
        let chart = makeChart(frame: .zero)
        let noViewport = invertedExpectation("No viewport before nonempty layout")
        let observer = ViewportRecorder(chart: chart, delivery: noViewport)
        observer.onReceive = { _ in XCTAssertTrue(Thread.isMainThread) }

        XCTAssertNil(chart.viewport)
        layout(chart)
        await fulfillment(of: [noViewport], timeout: 0.1)
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(observer.viewports.isEmpty)

        let initial = expectation(description: "Initial viewport")
        observer.delivery = initial
        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        await fulfillment(of: [initial], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100,
                           size: CGSize(width: 400, height: 300))
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testViewportBecomesUnavailableWhenEitherPlotDimensionBecomesEmpty() async throws {
        for emptyFrame in [
            CGRect(x: 0, y: 0, width: 40, height: 330),
            CGRect(x: 0, y: 0, width: 440, height: 30)
        ] {
            let chart = makeChart()
            layout(chart)
            let initial = expectation(description: "Initial viewport")
            let observer = ViewportRecorder(chart: chart, delivery: initial)
            await fulfillment(of: [initial], timeout: 2)
            XCTAssertNotNil(chart.viewport)
            observer.viewports.removeAll()

            let noViewport = invertedExpectation("No stale viewport for an empty plot")
            observer.delivery = noViewport
            chart.frame = emptyFrame
            layout(chart)
            XCTAssertNil(chart.viewport)
            await fulfillment(of: [noViewport], timeout: 0.1)

            XCTAssertNil(chart.viewport)
            XCTAssertTrue(observer.viewports.isEmpty)

            chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
            layout(chart)
            try assertViewport(chart.viewport, x: 0...1_000, y: 0...100)
        }
    }

    @MainActor
    func testZoomAndPanReportVisibleDataCoordinates() async throws {
        let chart = makeChart()
        layout(chart)
        let initial = expectation(description: "Initial viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        await fulfillment(of: [initial], timeout: 2)
        observer.viewports.removeAll()

        let zoomed = expectation(description: "Zoomed viewport")
        observer.delivery = zoomed
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        await fulfillment(of: [zoomed], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.last, x: 250...750, y: 25...75)

        let panned = expectation(description: "Panned viewport")
        observer.delivery = panned
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await fulfillment(of: [panned], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 2)
        try assertViewport(observer.viewports.last, x: 200...700, y: 30...80)
        XCTAssertEqual(chart.viewport, observer.viewports.last)
    }

    @MainActor
    func testResizeReportsNewPlotSizeAndCurrentVisibleDataRanges() async throws {
        let chart = makeChart()
        layout(chart)
        let initial = expectation(description: "Initial viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        await fulfillment(of: [initial], timeout: 2)

        let navigated = expectation(description: "Navigated viewport")
        observer.delivery = navigated
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await fulfillment(of: [navigated], timeout: 2)
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
        observer.viewports.removeAll()

        let resized = expectation(description: "Resized viewport")
        observer.delivery = resized
        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)
        await fulfillment(of: [resized], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        let transformer = chart.transformerProvider.transformer
        let topLeft = transformer.valueForTouchPoint(.zero)
        let bottomRight = transformer.valueForTouchPoint(CGPoint(x: 800, y: 500))
        try assertViewport(observer.viewports.first,
                           x: topLeft.x...bottomRight.x, y: bottomRight.y...topLeft.y,
                           size: CGSize(width: 800, height: 500))
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testCallbackAttachedAfterNavigationReceivesCurrentViewport() async throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))

        let settled = expectation(description: "Previous observer receives completed navigation")
        let previousObserver = ViewportRecorder(chart: chart, delivery: settled)
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(previousObserver.viewports.count, 1)

        let current = expectation(description: "Current viewport for a new observer")
        let observer = ViewportRecorder(chart: chart, delivery: current)
        await fulfillment(of: [current], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 200...700, y: 30...80)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testNavigationCallbacksAreDeferredAndCoalesceToCurrentViewport() async throws {
        let chart = makeChart()
        layout(chart)
        let initial = expectation(description: "Initial viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        var isMutatingNavigation = false
        observer.onReceive = { [weak chart] viewport in
            XCTAssertFalse(isMutatingNavigation, "Navigation must finish before notifying the application.")
            XCTAssertEqual(viewport, chart?.viewport, "The callback must expose the current, completed navigation state.")
        }
        await fulfillment(of: [initial], timeout: 2)
        observer.viewports.removeAll()

        let navigated = expectation(description: "Latest viewport after rapid navigation")
        observer.delivery = navigated
        isMutatingNavigation = true
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 0))
        XCTAssertTrue(observer.viewports.isEmpty, "Synchronous navigation must defer its callback.")
        isMutatingNavigation = false
        await fulfillment(of: [navigated], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 150...650, y: 30...80)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testNavigationInsideCallbackSchedulesFollowUpWithoutNestedCallbacks() async throws {
        let chart = makeChart()
        layout(chart)
        let delivered = expectation(description: "Initial viewport and callback-induced navigation")
        delivered.expectedFulfillmentCount = 2
        let observer = ViewportRecorder(chart: chart, delivery: delivered)
        var isHandlingCallback = false
        observer.onReceive = { [weak chart, weak observer] viewport in
            XCTAssertFalse(isHandlingCallback, "Application navigation must not invoke a nested callback.")
            isHandlingCallback = true
            defer { isHandlingCallback = false }
            XCTAssertEqual(viewport, chart?.viewport)

            if observer?.viewports.count == 1 {
                chart?.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
                XCTAssertEqual(observer?.viewports.count, 1, "Navigation from a callback must notify on a later turn.")
            }
        }
        XCTAssertTrue(observer.viewports.isEmpty)
        await fulfillment(of: [delivered], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 2)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100)
        try assertViewport(observer.viewports.last, x: 250...750, y: 0...100)
        XCTAssertEqual(chart.viewport, observer.viewports.last)
    }

    @MainActor
    func testProviderRedrawInsideViewportCallbackDoesNotCauseFeedbackOrMoveChart() async throws {
        let provider = ViewportTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        let initial = expectation(description: "Initial viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        observer.onReceive = { _ in
            // An application can replace displayed data in response to navigation.
            provider.redraw.send(())
        }
        await fulfillment(of: [initial], timeout: 2)
        XCTAssertEqual(observer.viewports.count, 1)
        observer.viewports.removeAll()

        let zoomed = expectation(description: "Zoomed viewport")
        observer.delivery = zoomed
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
        await fulfillment(of: [zoomed], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(chart.viewport, x: 250...750, y: 0...100)
        let navigatedViewport = chart.viewport

        let noViewport = invertedExpectation("Data redraws do not notify viewport observers")
        observer.delivery = noViewport
        provider.redraw.send(())
        provider.redraw.send(())
        await fulfillment(of: [noViewport], timeout: 0.1)

        XCTAssertEqual(observer.viewports.count, 1)
        XCTAssertEqual(chart.viewport, navigatedViewport)
    }

    @MainActor
    func testUnchangedLayoutAndNavigationDoNotRepeatNotification() async throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        let initial = expectation(description: "Current viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        await fulfillment(of: [initial], timeout: 2)
        observer.viewports.removeAll()
        let originalViewport = chart.viewport

        let noViewport = invertedExpectation("Unchanged viewport does not notify again")
        observer.delivery = noViewport
        layout(chart)
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 1, scaleY: 1, x: 173, y: 91)
        chart.transformerProvider.translate(delta: .zero)
        await fulfillment(of: [noViewport], timeout: 0.1)

        XCTAssertTrue(observer.viewports.isEmpty)
        XCTAssertEqual(chart.viewport, originalViewport)
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
    }

    @MainActor
    func testExistingRangePreparationUpdatesViewport() async throws {
        let chart = makeChart()
        layout(chart)
        let initial = expectation(description: "Initial viewport")
        let observer = ViewportRecorder(chart: chart, delivery: initial)
        await fulfillment(of: [initial], timeout: 2)
        observer.viewports.removeAll()

        let prepared = expectation(description: "Viewport after range preparation")
        observer.delivery = prepared
        chart.transformerProvider.prepareMatrixValuePx(
            dataRanges: DataRanges(chartXMin: 500, deltaX: 200, chartYMin: -20, deltaY: 40)
        )
        await fulfillment(of: [prepared], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 500...700, y: -20...20)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testFirstOnePointPlotReportsInitialViewportEvenWithUnchangedTransform() async throws {
        let chart = makeChart(frame: .zero)
        let noViewport = invertedExpectation("No viewport before the first valid layout")
        let observer = ViewportRecorder(chart: chart, delivery: noViewport)
        layout(chart)
        await fulfillment(of: [noViewport], timeout: 0.1)
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(observer.viewports.isEmpty)

        let initial = expectation(description: "First one-point viewport")
        observer.delivery = initial
        // The initial zero-sized view already uses a one-point transform.
        // Its first real layout must still make the viewport observable.
        chart.frame = CGRect(x: 0, y: 0, width: 41, height: 31)
        layout(chart)
        await fulfillment(of: [initial], timeout: 2)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100,
                           size: CGSize(width: 1, height: 1))
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    private func invertedExpectation(_ description: String) -> XCTestExpectation {
        let result = expectation(description: description)
        result.isInverted = true
        return result
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
}

@MainActor
private final class ViewportRecorder {
    var viewports: [ChartViewport] = []
    var delivery: XCTestExpectation {
        didSet { delivery.assertForOverFulfill = true }
    }
    var onReceive: ((ChartViewport) -> Void)?

    init(chart: InfiniteChartBase, delivery: XCTestExpectation) {
        self.delivery = delivery
        delivery.assertForOverFulfill = true
        chart.onViewportChange = { [weak self] viewport in
            guard let self else { return }
            self.viewports.append(viewport)
            self.onReceive?(viewport)
            self.delivery.fulfill()
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
