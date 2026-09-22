//
//  TransformerTests.swift
//  InfiniteChart
//
//  Created by Joshua Jiang on 8/17/24.
//

import Combine
import XCTest
@testable import InfiniteChart

class AffineTransformerTests: XCTestCase {
    var affineTransformerProvider: AffineTransformerProvider!

    override func setUp() {
        super.setUp()

        affineTransformerProvider = AffineTransformerProvider(
            size: CGSize(
                width: 100,
                height: 100
            ),
            dataRanges: DataRanges(
                chartXMin: 0,
                deltaX: 1000,
                chartYMin: 0,
                deltaY: 1000
            )
        )
    }

    func testNonZeroSetup() {
        affineTransformerProvider = AffineTransformerProvider(
            size: CGSize(
                width: 300,
                height: 800
            ),
            dataRanges: DataRanges(
                chartXMin: 10000,
                deltaX: 1000,
                chartYMin: 600,
                deltaY: 10
            )
        )

        var pixel = CGPoint(x: 0, y: 0)
        var value = DoublePrecisionPoint(x: 0, y: 0)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 10000)
        XCTAssertEqual(value.y, 610.0)

        pixel = CGPoint(x: 300, y: 800)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 11000.0)
        XCTAssertEqual(value.y, 600.0)

    }

    func testBasic() {
        var pixel = CGPoint(x: 50, y: 50)
        var value = DoublePrecisionPoint(x: 0, y: 0)

        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500.0)
        XCTAssertEqual(value.y, 500.0)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 1000.0)

        pixel = CGPoint(x: 100, y: 100)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000.0)
        XCTAssertEqual(value.y, 0.0)
    }

    func testZoomAtZero() {
        affineTransformerProvider.zoom(scaleX: 2, scaleY: 2)

        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 250)
        XCTAssertEqual(value.y, 750)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 0)
        XCTAssertEqual(value.y, 1000)

        pixel = CGPoint(x: 100, y: 100)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)
    }

    func testZoomAtCenter() {
        affineTransformerProvider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)

        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 250)
        XCTAssertEqual(value.y, 750)

        pixel = CGPoint(x: 100, y: 100)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 750)
        XCTAssertEqual(value.y, 250)
    }


    func testTranslate() {
        affineTransformerProvider.translate(delta: CGPoint(x: -50, y: -50))

        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 0)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 500)
        XCTAssertEqual(value.y, 500)

        pixel = CGPoint(x: 100, y: 100)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1500)
        XCTAssertEqual(value.y, -500)
    }

    func testTranslateAndZoom() {
        affineTransformerProvider.translate(delta: CGPoint(x: -50, y: -50))
        affineTransformerProvider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)

        // Test pixel to value
        var pixel = CGPoint(x: 50, y: 50)
        var value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1000)
        XCTAssertEqual(value.y, 0)

        pixel = CGPoint(x: 0, y: 0)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 750)
        XCTAssertEqual(value.y, 250)

        pixel = CGPoint(x: 100, y: 100)
        value = affineTransformerProvider.transformer.valueForTouchPoint(pixel)
        XCTAssertEqual(value.x, 1250)
        XCTAssertEqual(value.y, -250)
    }
}

extension AffineTransformerTests {
    func testTimestampCoordinatesRoundTripAndKeepZoomAnchor() {
        let provider = AffineTransformerProvider(
            size: CGSize(width: 1200, height: 600),
            dataRanges: DataRanges(chartXMin: 1_720_000_000_000, deltaX: 86_400_000,
                                   chartYMin: 59_000, deltaY: 2_000)
        )
        let anchor = CGPoint(x: 371.5, y: 214.25)
        let anchoredValue = provider.transformer.valueForTouchPoint(anchor)
        for _ in 0..<100 {
            provider.zoom(scaleX: 1.01, scaleY: 1.02, x: anchor.x, y: anchor.y)
        }
        let projected = provider.transformer.pixelForValue(anchoredValue)
        XCTAssertEqual(projected.x, anchor.x, accuracy: 0.00001)
        XCTAssertEqual(projected.y, anchor.y, accuracy: 0.00001)
        let point = DoublePrecisionPoint(x: 1_720_041_234_567, y: 60_123.456)
        let result = provider.transformer.valueForTouchPoint(provider.transformer.pixelForValue(point))
        XCTAssertEqual(result.x, point.x, accuracy: 0.001)
        XCTAssertEqual(result.y, point.y, accuracy: 0.000001)
    }

    func testZoomHasNoTimeUnitLimitAndVerticalZoomPreservesX() throws {
        let provider = AffineTransformerProvider(
            size: CGSize(width: 800, height: 400),
            dataRanges: DataRanges(chartXMin: 1_720_000_000_000, deltaX: 86_400_000,
                                   chartYMin: 0, deltaY: 100)
        )
        let initial = try XCTUnwrap(provider.viewport)
        provider.zoom(scaleX: 1, scaleY: 2, x: 333, y: 200)
        let vertical = try XCTUnwrap(provider.viewport)
        XCTAssertEqual(vertical.visibleXRange, initial.visibleXRange)
        XCTAssertEqual(vertical.visibleYRange.lowerBound, 25, accuracy: 0.000001)
        XCTAssertEqual(vertical.visibleYRange.upperBound, 75, accuracy: 0.000001)
        provider.zoom(scaleX: 0.5, scaleY: 1, x: 400, y: 200)
        let zoomedOut = try XCTUnwrap(provider.viewport)
        XCTAssertEqual(zoomedOut.visibleXRange.upperBound - zoomedOut.visibleXRange.lowerBound,
                       172_800_000, accuracy: 0.001)
    }

    func testInvalidGesturesCannotCorruptTransform() {
        let provider = affineTransformerProvider!
        let original = provider.transformer
        let originalViewport = provider.viewport
        var received = 0
        let subscription = provider.transformerStream.sink { _ in received += 1 }
        defer { withExtendedLifetime(subscription) {} }
        for scale: CGFloat in [0, -1, .nan, .infinity, .leastNonzeroMagnitude, .greatestFiniteMagnitude] {
            provider.zoom(scaleX: scale, scaleY: scale, x: 50, y: 50)
            XCTAssertEqual(provider.transformer, original)
        }
        // These matrices remain invertible, but their viewport endpoints collapse
        // to the same representable value and must be rejected before publication.
        provider.zoom(scaleX: 1e20, scaleY: 1, x: 50, y: 50)
        provider.translate(delta: CGPoint(x: 1e100, y: 0))
        provider.zoom(scaleX: 2, scaleY: 2, x: .nan, y: 50)
        provider.translate(delta: CGPoint(x: CGFloat.infinity, y: 0))
        provider.translate(delta: CGPoint(x: 0, y: CGFloat.nan))
        XCTAssertEqual(provider.transformer, original)
        XCTAssertEqual(provider.viewport, originalViewport)
        XCTAssertEqual(received, 1, "Rejected gestures must not publish a transform.")
        provider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        XCTAssertNotEqual(provider.transformer, original)
        XCTAssertEqual(received, 2)
    }

    func testInvalidRangesWaitForAValidRangeAndLaterInvalidUpdatesAreIgnored() {
        let provider = AffineTransformerProvider(
            size: .zero,
            dataRanges: DataRanges(chartXMin: 0, deltaX: 0, chartYMin: 0, deltaY: .nan)
        )
        XCTAssertNil(provider.viewport)
        provider.setChartDimens(width: 400, height: 300)
        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 0, deltaX: 100,
                                                            chartYMin: -10, deltaY: 20))
        XCTAssertNotNil(provider.viewport)
        let original = provider.transformer
        for invalid in [
            DataRanges(chartXMin: .infinity, deltaX: 100, chartYMin: 0, deltaY: 100),
            DataRanges(chartXMin: 0, deltaX: -100, chartYMin: 0, deltaY: 100),
            DataRanges(chartXMin: 0, deltaX: 100, chartYMin: 0, deltaY: 0),
            DataRanges(chartXMin: 1e20, deltaX: 1, chartYMin: 0, deltaY: 100)
        ] {
            provider.prepareMatrixValuePx(dataRanges: invalid)
            XCTAssertEqual(provider.transformer, original)
        }
    }

    func testOverflowingViewportCannotInitializeOrReplaceValidRanges() throws {
        let size = CGSize(width: 2, height: 1)
        let overflowingRanges = DataRanges(chartXMin: 0, deltaX: Double.greatestFiniteMagnitude,
                                          chartYMin: 0, deltaY: 1)
        // A finite, invertible matrix can still overflow across the plot width.
        let candidate = try XCTUnwrap(AffineTransformer(valueToPixel: CGAffineTransform(
            a: size.width / overflowingRanges.deltaX, b: 0, c: 0, d: -1, tx: 0, ty: 1
        )))
        XCTAssertFalse(candidate.valueForTouchPoint(CGPoint(x: 2, y: 1)).x.isFinite)

        let provider = AffineTransformerProvider(size: size, dataRanges: overflowingRanges)
        var received: [AffineTransformer] = []
        let subscription = provider.transformerStream.sink { received.append($0) }
        defer { withExtendedLifetime(subscription) {} }

        provider.prepareMatrixValuePx(dataRanges: overflowingRanges)
        XCTAssertFalse(provider.hasValidDataRanges)
        XCTAssertNil(provider.viewport)
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(CGSize(width: provider.chartWidth, height: provider.chartHeight), size)

        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 0, deltaX: 2,
                                                            chartYMin: 0, deltaY: 1))
        let original = provider.transformer
        let originalViewport = try XCTUnwrap(provider.viewport)
        XCTAssertEqual(received, [original])

        provider.prepareMatrixValuePx(dataRanges: overflowingRanges)
        XCTAssertTrue(provider.hasValidDataRanges)
        XCTAssertEqual(provider.transformer, original)
        XCTAssertEqual(provider.viewport, originalViewport)
        XCTAssertEqual(CGSize(width: provider.chartWidth, height: provider.chartHeight), size)
        XCTAssertEqual(received, [original], "An overflowing viewport must not publish or replace valid state.")
    }

    func testSubscribersReadCommittedTransformViewportAndDimensionsDuringEveryUpdate() throws {
        let provider = affineTransformerProvider!
        var expectedSize = CGSize(width: 100, height: 100)
        var viewports: [ChartViewport] = []
        let subscription = provider.transformerStream.sink { transformer in
            XCTAssertEqual(provider.transformer, transformer)
            XCTAssertEqual(CGSize(width: provider.chartWidth, height: provider.chartHeight), expectedSize)
            guard let viewport = provider.viewport else {
                XCTFail("A published transform must have a current viewport.")
                return
            }
            let topLeft = transformer.valueForTouchPoint(.zero)
            let bottomRight = transformer.valueForTouchPoint(CGPoint(x: expectedSize.width, y: expectedSize.height))
            XCTAssertEqual(viewport.visibleXRange, topLeft.x...bottomRight.x)
            XCTAssertEqual(viewport.visibleYRange, bottomRight.y...topLeft.y)
            XCTAssertEqual(viewport.plotSize, expectedSize)
            viewports.append(viewport)
        }
        defer { withExtendedLifetime(subscription) {} }

        XCTAssertEqual(viewports.count, 1)
        provider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        XCTAssertEqual(viewports.count, 2)
        XCTAssertEqual(try XCTUnwrap(viewports.last).visibleXRange, 250...750)
        provider.translate(delta: CGPoint(x: 10, y: 20))
        XCTAssertEqual(viewports.count, 3)
        XCTAssertEqual(try XCTUnwrap(viewports.last).visibleXRange, 200...700)
        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 500, deltaX: 200,
                                                            chartYMin: -20, deltaY: 40))
        XCTAssertEqual(viewports.count, 4)
        XCTAssertEqual(try XCTUnwrap(viewports.last).visibleXRange, 500...700)

        expectedSize = CGSize(width: 200, height: 300)
        provider.setChartDimens(width: expectedSize.width, height: expectedSize.height)
        XCTAssertEqual(viewports.count, 5)
        XCTAssertEqual(try XCTUnwrap(viewports.last).visibleXRange, 500...700)
        XCTAssertEqual(try XCTUnwrap(viewports.last).visibleYRange, -20...20)

        var lateTransforms: [AffineTransformer] = []
        let lateSubscription = provider.transformerStream.sink { lateTransforms.append($0) }
        defer { withExtendedLifetime(lateSubscription) {} }
        XCTAssertEqual(lateTransforms, [provider.transformer])
        XCTAssertEqual(viewports.count, 5, "Subscribing must not notify existing subscribers.")
    }

    func testFirstValidRangePublishesEvenWhenTransformMatchesPlaceholder() {
        let provider = AffineTransformerProvider(
            size: CGSize(width: 1, height: 1),
            dataRanges: DataRanges(chartXMin: 0, deltaX: 0, chartYMin: 0, deltaY: 0)
        )
        let placeholder = provider.transformer
        var received: [AffineTransformer] = []
        let subscription = provider.transformerStream.sink { transformer in
            XCTAssertTrue(provider.hasValidDataRanges)
            XCTAssertEqual(provider.transformer, transformer)
            XCTAssertNotNil(provider.viewport)
            received.append(transformer)
        }
        defer { withExtendedLifetime(subscription) {} }

        provider.zoom(scaleX: 2, scaleY: 2)
        provider.translate(delta: CGPoint(x: 10, y: 10))
        provider.setChartDimens(width: 1, height: 1)
        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 0, deltaX: 1,
                                                            chartYMin: 0, deltaY: 0))
        XCTAssertTrue(received.isEmpty)
        XCTAssertFalse(provider.hasValidDataRanges)
        XCTAssertNil(provider.viewport)

        let validRanges = DataRanges(chartXMin: 0, deltaX: 1, chartYMin: -1, deltaY: 1)
        provider.prepareMatrixValuePx(dataRanges: validRanges)
        XCTAssertEqual(provider.transformer, placeholder)
        XCTAssertEqual(received, [placeholder])
        XCTAssertEqual(provider.viewport, ChartViewport(visibleXRange: 0...1, visibleYRange: -1...0,
                                                       plotSize: CGSize(width: 1, height: 1)))

        provider.prepareMatrixValuePx(dataRanges: validRanges)
        XCTAssertEqual(received, [placeholder], "Repeating a valid range must remain silent.")
    }

    func testInvalidSizesAndUnchangedUpdatesPreserveStateWithoutPublishing() {
        let provider = affineTransformerProvider!
        let original = provider.transformer
        let originalViewport = provider.viewport
        var received = 0
        let subscription = provider.transformerStream.sink { _ in received += 1 }
        defer { withExtendedLifetime(subscription) {} }

        for size in [
            CGSize(width: 0, height: 100),
            CGSize(width: 100, height: -1),
            CGSize(width: CGFloat.nan, height: 100),
            CGSize(width: 100, height: CGFloat.infinity),
            CGSize(width: CGFloat.leastNonzeroMagnitude, height: 100),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        ] {
            provider.setChartDimens(width: size.width, height: size.height)
            XCTAssertEqual(provider.chartWidth, 100)
            XCTAssertEqual(provider.chartHeight, 100)
            XCTAssertEqual(provider.transformer, original)
            XCTAssertEqual(provider.viewport, originalViewport)
        }
        provider.setChartDimens(width: 100, height: 100)
        provider.zoom(scaleX: 1, scaleY: 1, x: 17, y: 31)
        provider.translate(delta: .zero)
        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 0, deltaX: 1000,
                                                            chartYMin: 0, deltaY: 1000))
        XCTAssertTrue(provider.hasValidDataRanges)
        XCTAssertEqual(provider.transformer, original)
        XCTAssertEqual(provider.viewport, originalViewport)
        XCTAssertEqual(received, 1)
    }
}
