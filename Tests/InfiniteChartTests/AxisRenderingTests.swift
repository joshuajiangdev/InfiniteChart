import Combine
import CoreGraphics
import XCTest
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import InfiniteChart

final class AxisRenderingTests: XCTestCase {
    /// Verifies that disabled label counts and invalid axis spacing normalize safely.
    func testDisabledLabelsAndInvalidSpaceAreSafe() async {
        await MainActor.run {
            for count in [0, -1, Int.min] {
                let config = AxisConfig(labelCount: count)
                XCTAssertEqual(config.labelCount, 0)
                XCTAssertTrue(AxisTicks.values(min: 0, max: 10, config: config).isEmpty)
            }
            for space: CGFloat in [-1, .nan, .infinity, -.infinity] {
                XCTAssertEqual(AxisConfig(requiredSpace: space).requiredSpace, 0)
            }
        }
    }

    /// Verifies finite, distinct, bounded ticks across reversed, tiny, and extreme ranges.
    func testTicksHandleReversedTinyAndExtremeRanges() async {
        await MainActor.run {
            let config = AxisConfig(labelCount: 6, centerAxisLabelsEnabled: false)
            let small = AxisTicks.values(min: 0, max: 0.00006, config: config)
            XCTAssertGreaterThan(small.count, 1, "Tick spacing must not assume a minimum price or time unit.")
            XCTAssertEqual(small, AxisTicks.values(min: 0.00006, max: 0, config: config))

            for (min, max) in [(0.0, Double.leastNonzeroMagnitude),
                               (1e20, 1e20 + 1e6), (-1e308, -9e307)] {
                let values = AxisTicks.values(min: min, max: max, config: config)
                XCTAssertFalse(values.isEmpty)
                XCTAssertTrue(values.allSatisfy(\.isFinite))
                XCTAssertEqual(values.count, Set(values).count)
                XCTAssertLessThanOrEqual(values.count, config.labelCount + 3)
            }
            let excessive = AxisTicks.values(min: 0, max: 1, config: AxisConfig(labelCount: .max))
            XCTAssertLessThanOrEqual(excessive.count, 1_003)
            for (min, max) in [(Double.nan, 1.0), (0, .infinity), (5, 5),
                               (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)] {
                XCTAssertTrue(AxisTicks.values(min: min, max: max, config: config).isEmpty)
            }
        }
    }

    /// Verifies repeated setup keeps one subscription and fits labels to the available axis width.
    func testAxisSetupReplacesSubscriptionAndUsesAvailableLabelWidth() async {
        await MainActor.run {
            #if !canImport(UIKit)
            _ = NSApplication.shared
            #endif
            let provider = AffineTransformerProvider(
                size: CGSize(width: 200, height: 100),
                dataRanges: DataRanges(chartXMin: 0, deltaX: 100, chartYMin: 0, deltaY: 100)
            )
            var subscriptions = 0
            let axis = YAxisView(frame: CGRect(x: 0, y: 0, width: 90, height: 100))
            axis.transformerStream = provider.transformerStream
                .handleEvents(receiveSubscription: { _ in subscriptions += 1 },
                              receiveCancel: { subscriptions -= 1 })
                .eraseToAnyPublisher()
            axis.setup()
            let count = axis.subviews.count
            axis.setup()
            axis.layoutChartSubviews()
            XCTAssertEqual(subscriptions, 1)
            XCTAssertEqual(axis.subviews.count, count)
            let labels = axis.subviews.compactMap { $0 as? AxisLabel }
            XCTAssertFalse(labels.isEmpty)
            XCTAssertTrue(labels.allSatisfy { $0.frame.minX == 0 && $0.frame.width == 90 })

            axis.config = AxisConfig(labelCount: 0)
            axis.setup()
            XCTAssertTrue(axis.subviews.isEmpty)
        }
    }

    /// Verifies that both axis borders render with their configured colors.
    func testAxisColorsDrawTheirBorders() async throws {
        try await MainActor.run {
            #if !canImport(UIKit)
            _ = NSApplication.shared
            #endif
            let xAxis = XAxisView(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
            xAxis.config = AxisConfig(axisColor: .red)
            let yAxis = YAxisView(frame: CGRect(x: 0, y: 0, width: 30, height: 100))
            yAxis.config = AxisConfig(axisColor: .blue)
            for (axis, channel) in [(xAxis as ChartPlatformView, 0), (yAxis as ChartPlatformView, 2)] {
                let pixels = try draw(axis)
                XCTAssertTrue(stride(from: 0, to: pixels.count, by: 4).contains {
                    pixels[$0 + channel] > 200 && pixels[$0 + 3] > 200
                })
            }
        }
    }

    /// Renders a view into RGBA bytes with the same downward Y direction on both native platforms.
    @MainActor
    private func draw(_ view: ChartPlatformView) throws -> [UInt8] {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        #if canImport(UIKit)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #else
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        #endif
        view.draw(view.bounds)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pixels, count: width * height * 4))
    }
}
