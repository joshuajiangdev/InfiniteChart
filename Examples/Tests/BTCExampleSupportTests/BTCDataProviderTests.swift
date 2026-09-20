import Combine
import Foundation
import XCTest
@testable import BTCExampleSupport

final class BTCDataProviderTests: XCTestCase {
    func testCoinbaseRowsBecomeAscendingMillisecondCandles() throws {
        let candles = try CoinbaseCandles.decode(Data("[[180,99,105,100,104,2.5],[60,90,100,92,99,1]]".utf8))

        XCTAssertEqual(candles.map(\.timestamp), [60_000, 180_000])
        XCTAssertEqual(candles[1].low, 99)
        XCTAssertEqual(candles[1].high, 105)
        XCTAssertEqual(candles[1].open, 100)
        XCTAssertEqual(candles[1].close, 104)
        XCTAssertEqual(candles[1].volume, 2.5)
        // Missing minutes are left missing rather than replaced with invented trading data.
        XCTAssertEqual(candles.count, 2)
    }

    func testRejectsMissingMalformedOrInvalidCandleData() {
        let invalidResponses = [
            "[]", "{}", "not JSON", "[[60,1,2,1,2]]", "[[60,1,2,1,2,3,4]]",
            "[[60,1,2,1,null,3]]", "[[60,1,2,1,2,-1]]", "[[60,3,2,1,2,3]]",
            "[[60,1,2,0,2,3]]", "[[60,1,2,1,3,3]]", "[[60,0,2,1,2,3]]",
            "[[61,1,2,1,2,3]]", "[[60.5,1,2,1,2,3]]", "[[0,1,2,1,2,3]]",
            "[[60,1,2,1,2,3],[60,1,2,1,2,3]]",
        ]
        for json in invalidResponses {
            XCTAssertThrowsError(try CoinbaseCandles.decode(Data(json.utf8)), json)
        }
    }

    func testSnapshotLoadsActualAttributedDataWithoutNetwork() throws {
        let provider = BTCDataProvider()

        XCTAssertNotNil(provider.getInitDataRanges())
        XCTAssertTrue(provider.isSnapshot)
        XCTAssertFalse(provider.isLoading)
        XCTAssertNil(provider.errorMessage)
        XCTAssertTrue(provider.sourceText.contains("Coinbase"))
        XCTAssertTrue(provider.sourceText.contains("historical snapshot"))
        XCTAssertTrue(provider.rangeText.contains("Aug 25, 2024 12:00"))
        XCTAssertTrue(provider.rangeText.contains("15:59 UTC"))
        XCTAssertTrue(provider.rangeText.contains("240 one-minute candles"))
        XCTAssertEqual(try XCTUnwrap(provider.getYValue(for: 1_724_601_540_000)), 64_163.32, accuracy: 0.0001)
        XCTAssertEqual(provider.technicalIndicators.first?.dataPoints.count, 231)
    }

    func testLookupsClampAtBoundsAndRespectDirectionAndOffsets() {
        let provider = BTCDataProvider(candles: candles([10, 20, 30, 40]))

        XCTAssertEqual(provider.getClosestXValue(to: 150_000, seekBelow: true, offset: 0), 120_000)
        XCTAssertEqual(provider.getClosestXValue(to: 150_000, seekBelow: false, offset: 0), 180_000)
        XCTAssertEqual(provider.getClosestXValue(to: 120_000, seekBelow: true, offset: 0), 120_000)
        XCTAssertEqual(provider.getClosestXValue(to: 120_000, seekBelow: false, offset: 0), 120_000)
        XCTAssertEqual(provider.getClosestXValue(to: 150_000, seekBelow: true, offset: 1), 60_000)
        XCTAssertEqual(provider.getClosestXValue(to: 150_000, seekBelow: false, offset: 1), 240_000)
        XCTAssertEqual(provider.getClosestXValue(to: 0, seekBelow: true, offset: Int.max), 60_000)
        XCTAssertEqual(provider.getClosestXValue(to: 1_000_000, seekBelow: false, offset: Int.max), 240_000)
        XCTAssertEqual(provider.getClosestXValue(to: 150_000, seekBelow: true, offset: -1), 120_000)
        XCTAssertNil(provider.getClosestXValue(to: .nan, seekBelow: true, offset: 0))
        XCTAssertNil(provider.getClosestXValue(to: .infinity, seekBelow: false, offset: 0))
    }

    func testPriceCandleAndVolumeLookupsUseExactTimestamps() throws {
        let provider = BTCDataProvider(candles: candles([10, 20]))

        XCTAssertEqual(provider.getYValue(for: 60_000), 10)
        let point = try XCTUnwrap(provider.getCandleStickDataPoint(for: 60_000))
        XCTAssertEqual(point.open, 9)
        XCTAssertEqual(point.close, 10)
        XCTAssertEqual(point.low, 8)
        XCTAssertEqual(point.high, 12)
        XCTAssertEqual(provider.getVolumeValueAndColor(for: 60_000)?.volume, 1)
        XCTAssertNil(provider.getYValue(for: 90_000))
        XCTAssertNil(provider.getCandleStickDataPoint(for: 90_000))
        XCTAssertNil(provider.getVolumeValueAndColor(for: 90_000))
    }

    func testMovingAveragesHaveFullWindowWarmupAndExpectedValues() {
        let input = candles([2, 4, 6, 10, 8])
        let sma = BTCIndicators.simpleMovingAverage(input, window: 3)
        let ema = BTCIndicators.exponentialMovingAverage(input, window: 3)

        XCTAssertEqual(sma.map(\.x), [180_000, 240_000, 300_000])
        XCTAssertEqual(sma[0].y, 4, accuracy: 0.0001)
        XCTAssertEqual(sma[1].y, 20.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(sma[2].y, 8, accuracy: 0.0001)
        XCTAssertEqual(ema.map(\.x), sma.map(\.x))
        XCTAssertEqual(ema.map(\.y), [4, 7, 7.5])
        XCTAssertTrue(BTCIndicators.simpleMovingAverage(input, window: 10).isEmpty)
        XCTAssertTrue(BTCIndicators.exponentialMovingAverage(input, window: 0).isEmpty)
    }

    func testIndicatorsToggleRedrawWithoutResettingViewport() {
        let provider = BTCDataProvider(candles: candles(Array(repeating: 100, count: 20)))
        let revision = provider.revision
        var redrawCount = 0
        let observation = provider.redrawStream.sink { redrawCount += 1 }

        XCTAssertEqual(redrawCount, 1, "New chart views must get an initial redraw.")
        XCTAssertEqual(provider.technicalIndicators.map(\.name), ["SMA(10)"])
        provider.showingEMA = true
        XCTAssertEqual(provider.technicalIndicators.map(\.name), ["SMA(10)", "EMA(10)"])
        provider.showingSMA = false
        XCTAssertEqual(provider.technicalIndicators.map(\.name), ["EMA(10)"])
        XCTAssertEqual(redrawCount, 3)
        XCTAssertEqual(provider.revision, revision)
        withExtendedLifetime(observation) {}
    }

    func testInitialRangesPadConstantPricesAndOneCandle() throws {
        let candle = BTCCandle(timestamp: 60_000, low: 100, high: 100, open: 100, close: 100, volume: 0)
        let provider = BTCDataProvider(candles: [candle])
        let ranges = try XCTUnwrap(provider.getInitDataRanges())

        XCTAssertLessThan(ranges.chartXMin, candle.timestamp)
        XCTAssertGreaterThan(ranges.chartXMin + ranges.deltaX, candle.timestamp)
        XCTAssertLessThan(ranges.chartYMin, candle.low)
        XCTAssertGreaterThan(ranges.chartYMin + ranges.deltaY, candle.high)
        XCTAssertGreaterThan(ranges.deltaX, 0)
        XCTAssertGreaterThan(ranges.deltaY, 0)
    }

    func testVisibleRangeUsesConfiguredTrailingCandles() throws {
        let provider = BTCDataProvider(candles: candles([1, 100, 101, 102]), visibleCandleCount: 2)
        let ranges = try XCTUnwrap(provider.getInitDataRanges())

        XCTAssertEqual(ranges.chartXMin, 120_000)
        XCTAssertGreaterThan(ranges.chartYMin, 90, "Old offscreen lows should not squash the initial chart.")
        XCTAssertGreaterThan(ranges.chartYMin + ranges.deltaY, 104)
    }

    func testEmptyProviderHasNoInvalidRangesOrLookups() {
        let provider = BTCDataProvider(candles: [])
        XCTAssertNil(provider.getInitDataRanges())
        XCTAssertNil(provider.getClosestXValue(to: 100, seekBelow: false, offset: 0))
        XCTAssertNil(provider.getYValue(for: 100))
        XCTAssertEqual(provider.latestPriceText, "—")
        XCTAssertEqual(provider.changeText, "No price data")
    }

    @MainActor
    func testRefreshReplacesDataAndRevisionAfterSuccessfulResponse() async {
        let provider = BTCDataProvider(candles: candles([10]), fetchData: { request in
            XCTAssertEqual(request.url?.host, "api.exchange.coinbase.com")
            XCTAssertEqual(request.url?.query, "granularity=60")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("[[120,100,110,101,108,3]]".utf8), response)
        })
        let revision = provider.revision

        await provider.refresh()

        XCTAssertEqual(provider.getYValue(for: 120_000), 108)
        XCTAssertNil(provider.getYValue(for: 60_000))
        XCTAssertNotEqual(provider.revision, revision)
        XCTAssertFalse(provider.isSnapshot)
        XCTAssertFalse(provider.isLoading)
        XCTAssertNil(provider.errorMessage)
        XCTAssertTrue(provider.sourceText.contains("fetched on demand"))
    }

    @MainActor
    func testHTTPErrorRetainsSnapshotAndViewport() async {
        let provider = BTCDataProvider(candles: candles([10]), fetchData: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        })
        let revision = provider.revision

        await provider.refresh()

        XCTAssertEqual(provider.getYValue(for: 60_000), 10)
        XCTAssertEqual(provider.revision, revision)
        XCTAssertTrue(provider.isSnapshot)
        XCTAssertFalse(provider.isLoading)
        XCTAssertTrue(provider.errorMessage?.contains("429") == true)
        XCTAssertTrue(provider.statusText.contains("keeping displayed candles"))
    }

    @MainActor
    func testDecodeAndNetworkErrorsRetainExistingData() async {
        let malformed = BTCDataProvider(candles: candles([10]), fetchData: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("[]".utf8), response)
        })
        let offline = BTCDataProvider(candles: candles([10]), fetchData: { _ in throw URLError(.notConnectedToInternet) })

        for provider in [malformed, offline] {
            let revision = provider.revision
            await provider.refresh()
            XCTAssertEqual(provider.getYValue(for: 60_000), 10)
            XCTAssertEqual(provider.revision, revision)
            XCTAssertTrue(provider.isSnapshot)
            XCTAssertFalse(provider.isLoading)
            XCTAssertNotNil(provider.errorMessage)
        }
    }

    private func candles(_ closes: [Double]) -> [BTCCandle] {
        closes.enumerated().map { index, close in
            BTCCandle(
                timestamp: Double(index + 1) * 60_000, low: close - 2, high: close + 2,
                open: close - 1, close: close, volume: Double(index + 1)
            )
        }
    }
}
