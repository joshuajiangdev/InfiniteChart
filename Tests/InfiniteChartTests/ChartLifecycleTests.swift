import Combine
import CoreGraphics
import XCTest
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import InfiniteChart

final class ChartLifecycleTests: XCTestCase {
    @MainActor
    func testEmptyProviderInitializesOnFirstValidRedrawAndPreservesNavigationOnLaterRedraws() async throws {
        let provider = LifecycleDataProvider(ranges: nil)
        let chart = makeChart(provider: provider)
        layout(chart)
        await drainDisplayUpdates()
        XCTAssertNil(chart.viewportStream.value)
        XCTAssertTrue(chart.xAxisView.subviews.isEmpty)
        XCTAssertTrue(chart.yAxisView.subviews.isEmpty)

        provider.redraw.send(())
        await drainDisplayUpdates()
        XCTAssertNil(chart.viewportStream.value, "A redraw without data must keep the viewport unavailable.")

        provider.ranges = DataRanges(chartXMin: 100, deltaX: 1_000, chartYMin: -20, deltaY: 100)
        provider.redraw.send(())
        await drainDisplayUpdates()

        XCTAssertFalse(chart.xAxisView.subviews.isEmpty)
        XCTAssertFalse(chart.yAxisView.subviews.isEmpty)
        let initial = try XCTUnwrap(chart.viewportStream.value)
        assertRange(initial.visibleXRange, equals: 100...1_100)
        assertRange(initial.visibleYRange, equals: -20...80)
        XCTAssertEqual(initial.plotSize, CGSize(width: 400, height: 300))

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        let navigated = try XCTUnwrap(chart.viewportStream.value)
        assertRange(navigated.visibleXRange, equals: 300...800)
        assertRange(navigated.visibleYRange, equals: 10...60)

        provider.ranges = DataRanges(chartXMin: 0, deltaX: 5_000, chartYMin: -100, deltaY: 500)
        provider.redraw.send(())
        await drainDisplayUpdates()
        XCTAssertEqual(chart.viewportStream.value, navigated,
                       "Data-only redraws must preserve the user's current view.")
    }

    @MainActor
    func testNavigationInvalidatesDrawingBeforeProviderEmitsItsFirstRedraw() async {
        let provider = LifecycleDataProvider(ranges: DataRanges(
            chartXMin: 0, deltaX: 1_000, chartYMin: 0, deltaY: 100
        ))
        let chart = makeChart(provider: provider)
        layout(chart)
        await drainDisplayUpdates()

        chart.displayInvalidations = 0
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        await drainDisplayUpdates()
        XCTAssertGreaterThan(chart.displayInvalidations, 0,
                             "A provider's redraw stream is an event stream; navigation must not wait for it.")

        chart.displayInvalidations = 0
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        await drainDisplayUpdates()
        XCTAssertGreaterThan(chart.displayInvalidations, 0)
    }

    @MainActor
    func testResizingPreservesNavigatedDataRanges() throws {
        let provider = LifecycleDataProvider(ranges: DataRanges(
            chartXMin: 0, deltaX: 1_000, chartYMin: 0, deltaY: 100
        ))
        let chart = makeChart(provider: provider)
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 40, y: 30))
        let beforeResize = try XCTUnwrap(chart.viewportStream.value)

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)

        let afterResize = try XCTUnwrap(chart.viewportStream.value)
        assertRange(afterResize.visibleXRange, equals: beforeResize.visibleXRange)
        assertRange(afterResize.visibleYRange, equals: beforeResize.visibleYRange)
        XCTAssertEqual(afterResize.plotSize, CGSize(width: 800, height: 500))
    }

    @MainActor
    private func makeChart(provider: LifecycleDataProvider) -> DisplayTrackingChart {
        #if !canImport(UIKit)
        _ = NSApplication.shared
        #endif
        return DisplayTrackingChart(
            frame: CGRect(x: 0, y: 0, width: 440, height: 330),
            dataProvider: provider,
            xAxisConfig: AxisConfig(requiredSpace: 30),
            yAxisConfig: AxisConfig(requiredSpace: 40)
        )
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
    private func drainDisplayUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func assertRange(
        _ range: ClosedRange<Double>, equals expected: ClosedRange<Double>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(range.lowerBound, expected.lowerBound, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(range.upperBound, expected.upperBound, accuracy: 0.0001, file: file, line: line)
    }
}

@MainActor
private final class DisplayTrackingChart: InfiniteChartBase {
    var displayInvalidations = 0

    #if canImport(UIKit)
    override func setNeedsDisplay() {
        displayInvalidations += 1
        super.setNeedsDisplay()
    }
    #else
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { displayInvalidations += 1 }
            super.needsDisplay = newValue
        }
    }
    #endif
}

private final class LifecycleDataProvider: ChartDataProviderBase {
    var ranges: DataRanges?
    let redraw = PassthroughSubject<Void, Never>()
    var redrawStream: AnyPublisher<Void, Never> { redraw.eraseToAnyPublisher() }
    var technicalIndicators: [TechnicalIndicator] { [] }

    init(ranges: DataRanges?) { self.ranges = ranges }

    func getInitDataRanges() -> DataRanges? { ranges }
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? { nil }
}
