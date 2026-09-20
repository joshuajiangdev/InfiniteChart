import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import InfiniteChart

final class ChartViewportTests: XCTestCase {
    @MainActor
    func testInitialViewportWaitsForNonemptyLayoutAndReportsDataRangesAndPlotSize() throws {
        let chart = makeChart(frame: .zero)
        let observer = ViewportRecorder(chart: chart)
        observer.onReceive = { _ in XCTAssertTrue(Thread.isMainThread) }

        XCTAssertNil(chart.viewport)
        layout(chart)
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(observer.viewports.isEmpty)

        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testViewportBecomesUnavailableWhenEitherPlotDimensionBecomesEmpty() throws {
        for emptyFrame in [
            CGRect(x: 0, y: 0, width: 40, height: 330),
            CGRect(x: 0, y: 0, width: 440, height: 30)
        ] {
            let chart = makeChart()
            layout(chart)
            let observer = ViewportRecorder(chart: chart)
            XCTAssertEqual(observer.viewports.count, 1)
            observer.viewports.removeAll()

            chart.frame = emptyFrame
            layout(chart)

            XCTAssertNil(chart.viewport)
            XCTAssertTrue(observer.viewports.isEmpty, "An empty plot must not emit a stale viewport.")

            chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
            layout(chart)
            try assertViewport(chart.viewport, x: 0...1_000, y: 0...100)
        }
    }

    @MainActor
    func testResizeReportsCompletedPlotSizeAndCurrentVisibleDataRanges() throws {
        let chart = makeChart()
        layout(chart)
        let observer = ViewportRecorder(chart: chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
        observer.viewports.removeAll()
        observer.onReceive = { [weak chart] viewport in
            XCTAssertEqual(viewport.plotSize, chart?.chartBaseView.bounds.size)
        }

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)

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
    func testLateSubscriberImmediatelyReceivesCurrentViewportWithoutNotifyingExistingSubscriber() throws {
        let chart = makeChart()
        layout(chart)
        let previousObserver = ViewportRecorder(chart: chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        XCTAssertEqual(previousObserver.viewports.count, 3)

        let observer = ViewportRecorder(chart: chart)

        XCTAssertEqual(observer.viewports.count, 1, "The current viewport must arrive during subscription.")
        try assertViewport(observer.viewports.first, x: 200...700, y: 30...80)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
        XCTAssertEqual(previousObserver.viewports.count, 3)
    }

    @MainActor
    func testEachNavigationPublishesItsNewTransformBeforeReturning() throws {
        let chart = makeChart()
        layout(chart)
        let observer = ViewportRecorder(chart: chart)
        observer.viewports.removeAll()

        // @Published sends the new transform before updating its stored value.
        // Each emitted viewport must describe that new transform immediately.
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.last, x: 250...750, y: 25...75)

        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        XCTAssertEqual(observer.viewports.count, 2)
        try assertViewport(observer.viewports.last, x: 200...700, y: 30...80)

        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 0))
        XCTAssertEqual(observer.viewports.count, 3)
        try assertViewport(observer.viewports.last, x: 150...650, y: 30...80)
        XCTAssertEqual(chart.viewport, observer.viewports.last)
    }

    @MainActor
    func testProviderRedrawInsideSubscriberDoesNotCauseFeedbackOrMoveChart() throws {
        let provider = ViewportTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        let observer = ViewportRecorder(chart: chart)
        observer.onReceive = { _ in provider.redraw.send(()) }
        observer.viewports.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(chart.viewport, x: 250...750, y: 0...100)
        let navigatedViewport = chart.viewport

        provider.redraw.send(())
        provider.redraw.send(())

        XCTAssertEqual(observer.viewports.count, 1)
        XCTAssertEqual(chart.viewport, navigatedViewport)
    }

    @MainActor
    func testUnchangedLayoutAndNavigationDoNotRepeatNotification() throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        let observer = ViewportRecorder(chart: chart)
        observer.viewports.removeAll()
        let originalViewport = chart.viewport

        layout(chart)
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 1, scaleY: 1, x: 173, y: 91)
        chart.transformerProvider.translate(delta: .zero)

        XCTAssertTrue(observer.viewports.isEmpty)
        XCTAssertEqual(chart.viewport, originalViewport)
        try assertViewport(chart.viewport, x: 200...700, y: 30...80)
    }

    @MainActor
    func testExistingRangePreparationUpdatesViewport() throws {
        let chart = makeChart()
        layout(chart)
        let observer = ViewportRecorder(chart: chart)
        observer.viewports.removeAll()

        chart.transformerProvider.prepareMatrixValuePx(
            dataRanges: DataRanges(chartXMin: 500, deltaX: 200, chartYMin: -20, deltaY: 40)
        )

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 500...700, y: -20...20)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testFirstOnePointPlotReportsInitialViewportEvenWithUnchangedTransform() throws {
        let chart = makeChart(frame: .zero)
        let observer = ViewportRecorder(chart: chart)
        layout(chart)
        XCTAssertNil(chart.viewport)
        XCTAssertTrue(observer.viewports.isEmpty)

        // The initial zero-sized view already uses a one-point transform.
        chart.frame = CGRect(x: 0, y: 0, width: 41, height: 31)
        layout(chart)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100,
                           size: CGSize(width: 1, height: 1))
        XCTAssertEqual(chart.viewport, observer.viewports.first)
    }

    @MainActor
    func testSubscribersReceiveIndependentlyAndCancellingOneKeepsTheOtherActive() throws {
        let chart = makeChart()
        layout(chart)
        let first = ViewportRecorder(chart: chart)
        let second = ViewportRecorder(chart: chart)
        XCTAssertEqual(first.viewports.count, 1)
        XCTAssertEqual(first.viewports, second.viewports)

        first.cancel()
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)

        XCTAssertEqual(first.viewports.count, 1)
        XCTAssertEqual(second.viewports.count, 2)
        try assertViewport(second.viewports.last, x: 250...750, y: 0...100)
    }

    @MainActor
    func testCancellationBeforeLayoutPreventsInitialAndNavigationNotifications() throws {
        let chart = makeChart(frame: .zero)
        let observer = ViewportRecorder(chart: chart)
        XCTAssertTrue(observer.viewports.isEmpty)
        observer.cancel()

        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)

        XCTAssertTrue(observer.viewports.isEmpty)
        try assertViewport(chart.viewport, x: 250...750, y: 0...100)
    }

    @MainActor
    func testSubscribingWhileEmptyDeliversWhenThePreviousPlotSizeIsRestored() throws {
        let chart = makeChart()
        layout(chart)
        XCTAssertNotNil(chart.viewport)
        chart.frame = CGRect(x: 0, y: 0, width: 40, height: 30)
        layout(chart)
        XCTAssertNil(chart.viewport)

        let observer = ViewportRecorder(chart: chart)
        XCTAssertTrue(observer.viewports.isEmpty)

        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)

        XCTAssertEqual(observer.viewports.count, 1)
        try assertViewport(observer.viewports.first, x: 0...1_000, y: 0...100)
        XCTAssertEqual(chart.viewport, observer.viewports.first)
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
    var onReceive: ((ChartViewport) -> Void)?
    private var subscription: AnyCancellable?

    init(chart: InfiniteChartBase) {
        subscription = chart.viewportStream.sink { [weak self] viewport in
            guard let self else { return }
            self.viewports.append(viewport)
            self.onReceive?(viewport)
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
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
