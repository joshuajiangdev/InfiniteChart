//
//  TransformerTests.swift
//  InfiniteChart
//
//  Created by Joshua Jiang on 8/17/24.
//

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
        let initial = try XCTUnwrap(provider.viewport(for: provider.transformer))
        provider.zoom(scaleX: 1, scaleY: 2, x: 333, y: 200)
        let vertical = try XCTUnwrap(provider.viewport(for: provider.transformer))
        XCTAssertEqual(vertical.visibleXRange, initial.visibleXRange)
        XCTAssertEqual(vertical.visibleYRange.lowerBound, 25, accuracy: 0.000001)
        XCTAssertEqual(vertical.visibleYRange.upperBound, 75, accuracy: 0.000001)
        provider.zoom(scaleX: 0.5, scaleY: 1, x: 400, y: 200)
        let zoomedOut = try XCTUnwrap(provider.viewport(for: provider.transformer))
        XCTAssertEqual(zoomedOut.visibleXRange.upperBound - zoomedOut.visibleXRange.lowerBound,
                       172_800_000, accuracy: 0.001)
    }

    func testInvalidGesturesCannotCorruptTransform() {
        let provider = affineTransformerProvider!
        let original = provider.transformer
        for scale: CGFloat in [0, -1, .nan, .infinity, .leastNonzeroMagnitude, .greatestFiniteMagnitude] {
            provider.zoom(scaleX: scale, scaleY: scale, x: 50, y: 50)
            XCTAssertEqual(provider.transformer, original)
        }
        provider.zoom(scaleX: 2, scaleY: 2, x: .nan, y: 50)
        provider.translate(delta: CGPoint(x: CGFloat.infinity, y: 0))
        provider.translate(delta: CGPoint(x: 0, y: CGFloat.nan))
        XCTAssertEqual(provider.transformer, original)
        provider.zoom(scaleX: 2, scaleY: 2, x: 50, y: 50)
        XCTAssertNotEqual(provider.transformer, original)
    }

    func testInvalidRangesWaitForAValidRangeAndLaterInvalidUpdatesAreIgnored() {
        let provider = AffineTransformerProvider(
            size: .zero,
            dataRanges: DataRanges(chartXMin: 0, deltaX: 0, chartYMin: 0, deltaY: .nan)
        )
        XCTAssertNil(provider.viewport(for: provider.transformer))
        provider.setChartDimens(width: 400, height: 300)
        provider.prepareMatrixValuePx(dataRanges: DataRanges(chartXMin: 0, deltaX: 100,
                                                            chartYMin: -10, deltaY: 20))
        XCTAssertNotNil(provider.viewport(for: provider.transformer))
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
}
