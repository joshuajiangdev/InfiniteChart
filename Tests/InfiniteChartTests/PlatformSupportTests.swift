import Combine
import CoreGraphics
import XCTest
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import InfiniteChart

final class PlatformSupportTests: XCTestCase {
    func testAxisFormattersRenderConsumerLabels() async {
        await MainActor.run {
            let chart = InfiniteChartBase(
                frame: CGRect(x: 0, y: 0, width: 440, height: 330),
                dataProvider: PlatformTestDataProvider(),
                xAxisConfig: AxisConfig(labelFormatter: { "time:\(Int($0))" }),
                yAxisConfig: AxisConfig(labelFormatter: { "price:\(Int($0))" })
            )
            layout(chart)
            let timeLabels = chart.xAxisView.subviews.compactMap { $0 as? AxisLabel }
            let priceLabels = chart.yAxisView.subviews.compactMap { $0 as? AxisLabel }
            XCTAssertFalse(timeLabels.isEmpty)
            XCTAssertFalse(priceLabels.isEmpty)
            XCTAssertTrue(timeLabels.allSatisfy { $0.text.hasPrefix("time:") })
            XCTAssertTrue(priceLabels.allSatisfy { $0.text.hasPrefix("price:") })
        }
    }

    func testChartUsesNativeViewsAndAcceptsNativeStyles() async {
        await MainActor.run {
            let font: ChartFont = .systemFont(ofSize: 17)
            let color: ChartColor = .red
            let config = AxisConfig(labelFont: font, labelColor: color, axisColor: .blue)
            let chart = makeChart(xAxisConfig: config)

            #if canImport(UIKit)
            let nativeView: UIView = chart
            let nativeFont: UIFont = config.labelFont
            let nativeColor: UIColor = config.labelColor
            #else
            let nativeView: NSView = chart
            let nativeFont: NSFont = config.labelFont
            let nativeColor: NSColor = config.labelColor
            XCTAssertTrue(chart.isFlipped, "Chart coordinates must increase downwards on macOS, too.")
            XCTAssertTrue(chart.chartBaseView.isFlipped)
            XCTAssertTrue(chart.xAxisView.isFlipped)
            XCTAssertTrue(chart.yAxisView.isFlipped)
            #endif

            XCTAssertTrue(chart.xAxisView.superview === nativeView)
            XCTAssertTrue(chart.yAxisView.superview === nativeView)
            XCTAssertTrue(chart.chartBaseView.superview === nativeView)
            XCTAssertEqual(nativeFont.pointSize, 17)
            XCTAssertEqual(nativeColor, color)
            XCTAssertNotNil(chart.candleStickRender)
            XCTAssertNotNil(chart.volumeRender)
        }
    }

    func testAxesAndPlotFollowNativeViewResizing() async {
        await MainActor.run {
            let chart = makeChart()
            layout(chart)

            XCTAssertEqual(chart.chartBaseView.frame, CGRect(x: 0, y: 0, width: 400, height: 300))
            XCTAssertEqual(chart.xAxisView.frame, CGRect(x: 0, y: 300, width: 400, height: 30))
            XCTAssertEqual(chart.yAxisView.frame, CGRect(x: 400, y: 0, width: 40, height: 300))

            chart.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            layout(chart)

            XCTAssertEqual(chart.chartBaseView.frame, CGRect(x: 0, y: 0, width: 600, height: 450))
            XCTAssertEqual(chart.xAxisView.frame, CGRect(x: 0, y: 450, width: 600, height: 30))
            XCTAssertEqual(chart.yAxisView.frame, CGRect(x: 600, y: 0, width: 40, height: 450))
        }
    }

    func testDataCoordinatesMatchPlotCornersBeforeAndAfterResize() async {
        await MainActor.run {
            let chart = makeChart()
            for size in [CGSize(width: 440, height: 330), CGSize(width: 640, height: 480)] {
                chart.frame = CGRect(origin: .zero, size: size)
                layout(chart)

                let transformer = chart.transformerProvider.transformer
                let topLeft = transformer.valueForTouchPoint(.zero)
                let bottomRightPixel = CGPoint(x: chart.chartBaseView.bounds.width,
                                               y: chart.chartBaseView.bounds.height)
                let bottomRight = transformer.valueForTouchPoint(bottomRightPixel)

                XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
                XCTAssertEqual(topLeft.y, 100, accuracy: 0.0001)
                XCTAssertEqual(bottomRight.x, 240_000, accuracy: 0.0001)
                XCTAssertEqual(bottomRight.y, 0, accuracy: 0.0001)

                let midpoint = transformer.pixelForValue(DoublePrecisionPoint(x: 120_000, y: 50))
                XCTAssertEqual(midpoint.x, bottomRightPixel.x / 2, accuracy: 0.0001)
                XCTAssertEqual(midpoint.y, bottomRightPixel.y / 2, accuracy: 0.0001)
            }
        }
    }

    func testInitiallyEmptyChartCanBeLaidOutAfterReceivingAFrame() async {
        await MainActor.run {
            let chart = makeChart(frame: .zero)
            layout(chart)
            chart.frame = CGRect(x: 0, y: 0, width: 440, height: 330)
            layout(chart)

            XCTAssertEqual(chart.chartBaseView.frame, CGRect(x: 0, y: 0, width: 400, height: 300))
            let midpoint = chart.transformerProvider.transformer.pixelForValue(DoublePrecisionPoint(x: 120_000, y: 50))
            XCTAssertEqual(midpoint.x, 200, accuracy: 0.0001)
            XCTAssertEqual(midpoint.y, 150, accuracy: 0.0001)
        }
    }

    func testNativePanGesturesMoveOnlyEnabledAxesAndClearDragState() async {
        await MainActor.run {
            let expectedPixels = [CGPoint(x: 235, y: 170), CGPoint(x: 235, y: 150), CGPoint(x: 200, y: 170)]
            for index in expectedPixels.indices {
                let chart = makeChart()
                layout(chart)
                let view: any Pannable
                switch index {
                case 0: view = chart.chartBaseView
                case 1: view = chart.xAxisView
                default: view = chart.yAxisView
                }

                let gesture = TestPanGestureRecognizer(target: nil, action: nil)
                gesture.testLocation = CGPoint(x: 10, y: 20)
                gesture.state = .began
                view.panGestureHandler(gesture)
                gesture.testLocation = CGPoint(x: 45, y: 40)
                gesture.state = .changed
                view.panGestureHandler(gesture)

                let pixel = chart.transformerProvider.transformer.pixelForValue(DoublePrecisionPoint(x: 120_000, y: 50))
                XCTAssertEqual(pixel.x, expectedPixels[index].x, accuracy: 0.0001)
                XCTAssertEqual(pixel.y, expectedPixels[index].y, accuracy: 0.0001)
                XCTAssertEqual(view.lastDragPoint, gesture.testLocation)

                gesture.state = .ended
                view.panGestureHandler(gesture)
                XCTAssertNil(view.lastDragPoint)

                layout(chart)
                let pixelAfterLayout = chart.transformerProvider.transformer.pixelForValue(DoublePrecisionPoint(x: 120_000, y: 50))
                XCTAssertEqual(pixelAfterLayout.x, pixel.x, accuracy: 0.0001)
                XCTAssertEqual(pixelAfterLayout.y, pixel.y, accuracy: 0.0001)
            }
        }
    }

    func testNativePinchGesturesZoomEnabledAxesAndResetIncrementalScale() async {
        await MainActor.run {
            let expectedPixels = [CGPoint(x: 150, y: 90), CGPoint(x: 0, y: 75), CGPoint(x: 100, y: 0)]
            for index in expectedPixels.indices {
                let chart = makeChart()
                layout(chart)
                let view: any Pinchable
                switch index {
                case 0: view = chart.chartBaseView
                case 1: view = chart.xAxisView
                default: view = chart.yAxisView
                }

                let gesture = TestPinchGestureRecognizer(target: nil, action: nil)
                if index == 2 {
                    // Tightening X limits must not let a Y-axis pinch change X.
                    chart.xSpanLimits = 60_000...120_000
                }
                gesture.testLocation = CGPoint(x: 50, y: 60)
                gesture.state = .changed
                #if canImport(UIKit)
                gesture.scale = 2
                #else
                gesture.magnification = 1
                #endif
                view.pinchGestureHandler(gesture)

                let sample = DoublePrecisionPoint(x: 60_000, y: 75)
                let pixel = chart.transformerProvider.transformer.pixelForValue(sample)
                XCTAssertEqual(pixel.x, expectedPixels[index].x, accuracy: 0.0001)
                XCTAssertEqual(pixel.y, expectedPixels[index].y, accuracy: 0.0001)
                #if canImport(UIKit)
                XCTAssertEqual(gesture.scale, 1)
                #else
                XCTAssertEqual(gesture.magnification, 0)
                #endif

                view.pinchGestureHandler(gesture)
                let unchangedPixel = chart.transformerProvider.transformer.pixelForValue(sample)
                XCTAssertEqual(unchangedPixel.x, pixel.x, accuracy: 0.0001)
                XCTAssertEqual(unchangedPixel.y, pixel.y, accuracy: 0.0001)

                layout(chart)
                let pixelAfterLayout = chart.transformerProvider.transformer.pixelForValue(sample)
                XCTAssertEqual(pixelAfterLayout.x, pixel.x, accuracy: 0.0001)
                XCTAssertEqual(pixelAfterLayout.y, pixel.y, accuracy: 0.0001)
            }
        }
    }

    func testNativeDrawingIncludesLastAvailableCandleAndVolume() async throws {
        try await MainActor.run {
            let chart = makeChart()
            layout(chart)
            let pixels = try render(chart)
            let lastCandleX = 300 // 180,000 ms in a 400-point, 240,000 ms plot.
            let column = (0..<330).map { ($0 * 440 + lastCandleX) * 4 }
            XCTAssertTrue(column.contains { pixels[$0] > 180 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 })
            XCTAssertTrue(column.contains { pixels[$0 + 2] > 180 && pixels[$0] < 80 && pixels[$0 + 1] < 80 })
        }
    }

    func testNativeDrawingRendersCandlesVolumesAndTechnicalIndicators() async throws {
        try await MainActor.run {
            let chart = makeChart()
            layout(chart)
            let pixels = try render(chart)
            var candlePixels = 0
            var volumePixels = 0
            var indicatorPixels = 0

            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                guard pixels[offset + 3] > 180 else { continue }
                if red > 180 && green < 80 && blue < 80 { candlePixels += 1 }
                if blue > 180 && red < 80 && green < 80 { volumePixels += 1 }
                if red > 180 && blue > 180 && green < 80 { indicatorPixels += 1 }
            }

            XCTAssertGreaterThan(candlePixels, 10, "Native draw(_:) must render red candle bodies.")
            XCTAssertGreaterThan(volumePixels, 10, "Native draw(_:) must render blue volume bars.")
            XCTAssertGreaterThan(indicatorPixels, 10, "Native draw(_:) must render the magenta indicator.")
        }
    }

    func testPartialNativeRedrawPreservesChartGeometry() async throws {
        try await MainActor.run {
            let chart = makeChart()
            layout(chart)
            let dirtyRect = CGRect(x: 190, y: 260, width: 20, height: 30)
            let fullDrawing = try render(chart, clipTo: dirtyRect)
            let partialDrawing = try render(chart, dirtyRect: dirtyRect, clipTo: dirtyRect)

            XCTAssertTrue(fullDrawing.contains(where: { $0 != 0 }), "The dirty area must contain a volume bar.")
            XCTAssertTrue(partialDrawing == fullDrawing, "A partial redraw must retain the full chart's geometry.")
        }
    }

    func testAxisLabelsDrawHorizontalAndRotatedText() async throws {
        try await MainActor.run {
            let horizontalLabel = AxisLabel(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
            horizontalLabel.text = "123.45"
            horizontalLabel.font = .systemFont(ofSize: 17)
            let horizontalBounds = try opaquePixelBounds(try render(horizontalLabel), width: 100)
            XCTAssertGreaterThan(horizontalBounds.width, horizontalBounds.height)

            let rotatedLabel = AxisLabel(frame: CGRect(x: 0, y: 0, width: 30, height: 100))
            rotatedLabel.text = "123.45"
            rotatedLabel.font = .systemFont(ofSize: 17)
            rotatedLabel.rotationAngle = .pi / 2
            let rotatedBounds = try opaquePixelBounds(try render(rotatedLabel), width: 30)
            XCTAssertGreaterThan(rotatedBounds.height, rotatedBounds.width)
        }
    }

    @MainActor
    private func makeChart(
        xAxisConfig: AxisConfig = AxisConfig(requiredSpace: 30),
        frame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 330)
    ) -> InfiniteChartBase {
        #if !canImport(UIKit)
        _ = NSApplication.shared
        #endif
        return InfiniteChartBase(
            frame: frame,
            dataProvider: PlatformTestDataProvider(),
            xAxisConfig: xAxisConfig,
            yAxisConfig: AxisConfig(requiredSpace: 40)
        )
    }

    @MainActor
    private func layout(_ chart: InfiniteChartBase) {
        #if canImport(UIKit)
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        #else
        chart.needsLayout = true
        chart.layoutSubtreeIfNeeded()
        #endif
    }

    @MainActor
    private func render(_ view: ChartPlatformView, dirtyRect: CGRect? = nil, clipTo: CGRect? = nil) throws -> [UInt8] {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        let bytesPerRow = width * 4
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        if let clipTo { context.clip(to: clipTo) }

        #if canImport(UIKit)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #else
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        #endif

        view.draw(dirtyRect ?? view.bounds)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: bytesPerRow * height))
    }

    private func opaquePixelBounds(_ pixels: [UInt8], width: Int) throws -> CGRect {
        let indices = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 100 }.map { $0 / 4 }
        let minX = try XCTUnwrap(indices.map { $0 % width }.min(), "The label must render visible text.")
        let maxX = try XCTUnwrap(indices.map { $0 % width }.max())
        let minY = try XCTUnwrap(indices.map { $0 / width }.min())
        let maxY = try XCTUnwrap(indices.map { $0 / width }.max())
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

#if canImport(UIKit)
private typealias NativeTestView = UIView
private typealias NativeTestGestureState = UIGestureRecognizer.State
#else
private typealias NativeTestView = NSView
private typealias NativeTestGestureState = NSGestureRecognizer.State
#endif

private final class TestPanGestureRecognizer: ChartPanGestureRecognizer {
    var testLocation: CGPoint = .zero
    private var testState: NativeTestGestureState = .possible

    override var state: NativeTestGestureState {
        get { testState }
        set { testState = newValue }
    }

    override func location(in view: NativeTestView?) -> CGPoint { testLocation }
}

private final class TestPinchGestureRecognizer: ChartPinchGestureRecognizer {
    var testLocation: CGPoint = .zero
    private var testState: NativeTestGestureState = .possible

    override var state: NativeTestGestureState {
        get { testState }
        set { testState = newValue }
    }

    override func location(in view: NativeTestView?) -> CGPoint { testLocation }
}

private struct PlatformTestDataProvider: CandleStickDataProvider, VolumeDataProvider {
    let redrawStream = Just(()).eraseToAnyPublisher()
    let tranformerUpdatedDelegate: ChartDataProviderDelegate? = nil
    let technicalIndicators = [TechnicalIndicator(
        name: "Test indicator",
        color: .magenta,
        dataPoints: [(x: 60_000, y: 40), (x: 180_000, y: 40)]
    )]

    func getInitDataRanges() -> DataRanges? {
        DataRanges(chartXMin: 0, deltaX: 240_000, chartYMin: 0, deltaY: 100)
    }

    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? {
        let index = (xValue / 60_000).rounded(seekBelow ? .down : .up)
        return min(180_000, max(60_000, (index + Double(seekBelow ? -offset : offset)) * 60_000))
    }

    func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint? {
        guard (60_000...180_000).contains(xValue) else { return nil }
        return CandleStickDataPoint(high: 90, low: 60, open: 70, close: 80, color: .red)
    }

    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)? {
        guard (60_000...180_000).contains(xValue) else { return nil }
        return (volume: xValue / 60_000, color: .blue)
    }
}
