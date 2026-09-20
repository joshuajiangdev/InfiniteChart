import Combine
import XCTest
@testable import InfiniteChart

final class ChartNavigationTests: XCTestCase {

    @MainActor
    func testNavigationAndResizePreserveVisibleRange() throws {
        let chart = makeChart()
        layout(chart)
        var changes: [ChartViewport] = []
        let viewportObservation = chart.viewportStream.compactMap { $0 }.sink {
            changes.append($0)
        }
        defer { withExtendedLifetime(viewportObservation) {} }
        XCTAssertEqual(changes.count, 1, "A subscription immediately receives the current viewport.")
        changes.removeAll()

        chart.transformerProvider.zoom(scaleX: 2, scaleY: 1, x: 200, y: 150)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.last, chart.viewportStream.value)
        chart.transformerProvider.translate(delta: CGPoint(x: 20, y: 0))
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.last, chart.viewportStream.value)
        let beforeResize = try XCTUnwrap(chart.viewportStream.value)

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)
        let afterResize = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes.last, afterResize)
        XCTAssertEqual(afterResize.plotSize, CGSize(width: 800, height: 500))
        XCTAssertEqual(afterResize.visibleXRange.lowerBound, beforeResize.visibleXRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleXRange.upperBound, beforeResize.visibleXRange.upperBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleYRange.lowerBound, beforeResize.visibleYRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(afterResize.visibleYRange.upperBound, beforeResize.visibleYRange.upperBound, accuracy: 0.0001)
    }

    @MainActor
    func testEmptyPlotThenResizePreservesZoomAndPan() throws {
        let chart = makeChart()
        layout(chart)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 20, y: 10))
        let beforeEmptyPlot = try XCTUnwrap(chart.viewportStream.value)
        var changes: [ChartViewport?] = []
        let viewportObservation = chart.viewportStream.sink { changes.append($0) }
        defer { withExtendedLifetime(viewportObservation) {} }

        chart.frame = .zero
        layout(chart)
        XCTAssertNil(chart.viewportStream.value)
        XCTAssertEqual(changes.count, 2, "An empty plot must publish nil after the initial viewport.")
        XCTAssertNil(changes.last ?? nil)

        chart.frame = CGRect(x: 0, y: 0, width: 840, height: 530)
        layout(chart)
        let restored = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes.last ?? nil, restored)
        XCTAssertEqual(restored.plotSize, CGSize(width: 800, height: 500))
        XCTAssertEqual(restored.visibleXRange.lowerBound, beforeEmptyPlot.visibleXRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(restored.visibleXRange.upperBound, beforeEmptyPlot.visibleXRange.upperBound, accuracy: 0.0001)
        XCTAssertEqual(restored.visibleYRange.lowerBound, beforeEmptyPlot.visibleYRange.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(restored.visibleYRange.upperBound, beforeEmptyPlot.visibleYRange.upperBound, accuracy: 0.0001)
    }

    @MainActor
    func testApplicationDataRedrawDoesNotResetViewportOrCauseFeedback() throws {
        let provider = NavigationTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        var changes: [ChartViewport] = []
        let viewportObservation = chart.viewportStream.compactMap { $0 }.sink { change in
            changes.append(change)
            // Equivalent to the app replacing its resolution on a viewport event.
            provider.redraw.send(())
        }
        defer { withExtendedLifetime(viewportObservation) {} }
        XCTAssertEqual(changes.count, 1, "A subscription immediately receives the current viewport.")
        changes.removeAll()
        chart.setVisibleXRange(200...700)
        XCTAssertEqual(changes.count, 1)
        let selectedViewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(changes.first, selectedViewport)
        provider.redraw.send(())
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(chart.viewportStream.value, selectedViewport)
        chart.resetViewport()
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(try XCTUnwrap(chart.viewportStream.value).visibleXRange.upperBound, 1_000, accuracy: 0.0001)
    }

    @MainActor
    func testVerticalFitPreservesHorizontalNavigationAndReportsOneChange() throws {
        let provider = NavigationTestProvider()
        let chart = makeChart(provider: provider)
        layout(chart)
        chart.setVisibleXRange(1_724_587_201_234...1_724_590_801_789)
        chart.transformerProvider.zoom(scaleX: 1.37, scaleY: 1, x: 173, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 17.3, y: 0))
        let originalXRange = try XCTUnwrap(chart.viewportStream.value).visibleXRange
        // Setting horizontal limits must not make a subsequent Y-only fit move X.
        chart.xSpanLimits = 60_000...120_000
        var changes: [ChartViewport] = []
        let viewportObservation = chart.viewportStream.compactMap { $0 }.sink { change in
            changes.append(change)
            provider.redraw.send(())
        }
        defer { withExtendedLifetime(viewportObservation) {} }
        XCTAssertEqual(changes.count, 1, "A subscription immediately receives the current viewport.")
        changes.removeAll()

        chart.setVisibleYRange(50_000...75_000)
        let fittedViewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(fittedViewport.visibleXRange, originalXRange, "A vertical fit must leave horizontal navigation exactly unchanged.")
        XCTAssertEqual(fittedViewport.visibleYRange.lowerBound, 50_000, accuracy: 0.0001)
        XCTAssertEqual(fittedViewport.visibleYRange.upperBound, 75_000, accuracy: 0.0001)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first, fittedViewport)

        provider.redraw.send(())
        XCTAssertEqual(changes.count, 1, "Replacing data must not repeat the viewport notification.")
        XCTAssertEqual(chart.viewportStream.value, fittedViewport, "A data redraw must retain both fitted ranges.")
    }

    @MainActor
    func testInvalidVerticalRangesAreIgnoredWithoutNotifying() throws {
        let chart = makeChart(frame: .zero)
        chart.setVisibleYRange(10...20)
        XCTAssertNil(chart.viewportStream.value)
        chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
        layout(chart)
        // Negative values are valid; only the span must be positive.
        chart.setVisibleYRange(-200 ... -50)
        var changes: [ChartViewport] = []
        let viewportObservation = chart.viewportStream.compactMap { $0 }.sink {
            changes.append($0)
        }
        defer { withExtendedLifetime(viewportObservation) {} }
        XCTAssertEqual(changes.count, 1, "A subscription immediately receives the current viewport.")
        changes.removeAll()
        let original = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(original.visibleYRange.lowerBound, -200, accuracy: 0.0001)
        XCTAssertEqual(original.visibleYRange.upperBound, -50, accuracy: 0.0001)

        chart.setVisibleYRange(1...1)
        chart.setVisibleYRange(0...Double.infinity)
        chart.setVisibleYRange(-Double.infinity...0)
        chart.setVisibleYRange(-Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
        XCTAssertEqual(chart.viewportStream.value, original)
        XCTAssertTrue(changes.isEmpty)
    }

    @MainActor
    func testSpanLimitsUseProviderUnitsAndPreserveZoomAnchor() throws {
        let chart = makeChart()
        layout(chart)
        chart.xSpanLimits = 200...2_000
        chart.transformerProvider.zoom(scaleX: 0.01, scaleY: 1, x: 200, y: 150)
        var viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound, 2_000, accuracy: 0.0001)
        XCTAssertEqual((viewport.visibleXRange.lowerBound + viewport.visibleXRange.upperBound) / 2, 500, accuracy: 0.0001)
        chart.setVisibleXRange(490...510)
        viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 400, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 600, accuracy: 0.0001)

        chart.xSpanLimits = nil
        chart.setVisibleXRange(0...(24 * 60 * 60_000))
        chart.transformerProvider.zoom(scaleX: 0.5, scaleY: 1)
        viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound, 48 * 60 * 60_000, accuracy: 0.001)
    }

    @MainActor
    func testVerticalOnlyZoomPreservesXRangeAfterSpanLimitsChange() throws {
        for limits in [200.0...400.0, 2_000.0...4_000.0] {
            for scaleY in [0.5, 1.0, 2.0] {
                let chart = makeChart()
                layout(chart)
                let original = try XCTUnwrap(chart.viewportStream.value)
                // Both a lower maximum and a higher minimum exclude the current X span.
                chart.xSpanLimits = limits
                var changes: [ChartViewport] = []
                let viewportObservation = chart.viewportStream.compactMap { $0 }.sink {
                    changes.append($0)
                }
                defer { withExtendedLifetime(viewportObservation) {} }
                XCTAssertEqual(changes.count, 1, "A subscription immediately receives the current viewport.")
                changes.removeAll()

                chart.transformerProvider.zoom(scaleX: 1, scaleY: scaleY, x: 0, y: 150)

                let zoomed = try XCTUnwrap(chart.viewportStream.value)
                XCTAssertEqual(zoomed.visibleXRange, original.visibleXRange)
                XCTAssertEqual(zoomed.visibleYRange.lowerBound, 50 - 50 / scaleY, accuracy: 0.0001)
                XCTAssertEqual(zoomed.visibleYRange.upperBound, 50 + 50 / scaleY, accuracy: 0.0001)
                if scaleY == 1 {
                    XCTAssertTrue(changes.isEmpty, "An unchanged gesture must not move the viewport.")
                } else {
                    XCTAssertEqual(changes.count, 1)
                    XCTAssertEqual(changes.first, zoomed)
                }
            }
        }
    }

    @MainActor
    func testInitialLayoutAndResetRespectSpanLimits() throws {
        let chart = makeChart()
        chart.xSpanLimits = 200...400
        layout(chart)
        var viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 300, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 700, accuracy: 0.0001)
        chart.transformerProvider.zoom(scaleX: 2, scaleY: 2, x: 200, y: 150)
        chart.transformerProvider.translate(delta: CGPoint(x: 10, y: 10))
        chart.resetViewport()
        viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange.lowerBound, 300, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleXRange.upperBound, 700, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleYRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewport.visibleYRange.upperBound, 100, accuracy: 0.0001)
    }

    @MainActor
    func testInvalidNavigationDoesNotCorruptViewport() throws {
        let chart = makeChart()
        layout(chart)
        let original = try XCTUnwrap(chart.viewportStream.value)
        chart.setVisibleXRange(1...1)
        chart.setVisibleXRange(0...Double.infinity)
        chart.transformerProvider.zoom(scaleX: 0, scaleY: 1)
        chart.transformerProvider.zoom(scaleX: .infinity, scaleY: 1)
        chart.transformerProvider.translate(delta: CGPoint(x: CGFloat.nan, y: 0))
        XCTAssertEqual(chart.viewportStream.value, original)
    }

    @MainActor
    private func makeChart(frame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 330),
                           provider: NavigationTestProvider = NavigationTestProvider()) -> InfiniteChartBase {
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

private final class NavigationTestProvider: ChartDataProviderBase {
    let redraw = CurrentValueSubject<Void, Never>(())
    var redrawStream: AnyPublisher<Void, Never> { redraw.eraseToAnyPublisher() }
    weak var tranformerUpdatedDelegate: (any ChartDataProviderDelegate)?
    var technicalIndicators: [TechnicalIndicator] { [] }
    func getInitDataRanges() -> DataRanges? {
        DataRanges(chartXMin: 0, deltaX: 1_000, chartYMin: 0, deltaY: 100)
    }
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? { nil }
}
