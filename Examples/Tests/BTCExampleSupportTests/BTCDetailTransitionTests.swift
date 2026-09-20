import Combine
import Foundation
import InfiniteChart
import XCTest
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import BTCExampleSupport

@MainActor
final class BTCDetailTransitionTests: XCTestCase {
    func testRemoteLevelsUseServerOHLCVAndRequestResolutionSpecificHistory() async throws {
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport)
        let revision = provider.revision
        let reset = try XCTUnwrap(provider.getInitDataRanges())

        for (spacing, interval) in [(2.0, 5), (0.5, 15), (10.0, 1)] {
            // The final 1m view is outside the bundled minute cache, so it must fetch too.
            let center = interval == 1 ? fixtureStart + 7 * day : fixtureCenter
            let viewport = viewport(pointsPerMinute: spacing, center: center)
            provider.updateViewport(viewport)
            await provider.waitForPendingRequest()

            XCTAssertEqual(provider.candleIntervalMinutes, interval)
            XCTAssertEqual(provider.nominalXStep, Double(interval) * minute)
            XCTAssertEqual(provider.revision, revision)
            XCTAssertFalse(provider.isLoading)
            XCTAssertNil(provider.errorMessage)
            let requests = await transport.requests
            let info = try RequestInfo(try XCTUnwrap(requests.last))
            XCTAssertEqual(info.granularity, interval * 60)
            let intervalRequests = try requests.filter { try RequestInfo($0).granularity == interval * 60 }
            let starts = try intervalRequests.map { try XCTUnwrap(RequestInfo($0).start) }
            let ends = try intervalRequests.map { try XCTUnwrap(RequestInfo($0).end) }
            XCTAssertLessThanOrEqual(try XCTUnwrap(starts.min()), viewport.visibleXRange.lowerBound)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ends.max()), viewport.visibleXRange.upperBound)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ends.max()) - XCTUnwrap(starts.min()), Double(interval) * minute * 239)
            let timestamp = try XCTUnwrap(provider.getXValues(in: viewport.visibleXRange).first)
            let candle = try XCTUnwrap(provider.getCandleStickDataPoint(for: timestamp))
            XCTAssertEqual(candle.open, serverPrice(interval) - 2)
            XCTAssertEqual(candle.high, serverPrice(interval) + 5)
            XCTAssertEqual(candle.low, serverPrice(interval) - 5)
            XCTAssertEqual(candle.close, serverPrice(interval))
            XCTAssertEqual(provider.getVolumeValueAndColor(for: timestamp)?.volume, Double(interval) * 123)
            XCTAssertGreaterThan(candle.low, 1_000, "Server bars must not be synthesized from the ~100-dollar fixture.")
            assertSameRanges(try XCTUnwrap(provider.getInitDataRanges()), reset)
        }
        let granularities = try await transport.requests.map { try RequestInfo($0).granularity }
        XCTAssertTrue(granularities.contains(60))
        XCTAssertTrue(granularities.contains(300))
        XCTAssertTrue(granularities.contains(900))
    }

    func testPriceVolumeAndIndicatorsArePublishedAsOneRemoteSnapshot() async throws {
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport)
        provider.showingEMA = true
        var observations: [Int] = []
        let observation = provider.redrawStream.sink {
            observations.append(provider.candleIntervalMinutes)
            guard provider.candleIntervalMinutes != 1 else { return }
            let interval = provider.candleIntervalMinutes
            let timestamps = provider.getXValues(in: 0...Double.greatestFiniteMagnitude)
            for timestamp in timestamps {
                XCTAssertEqual(provider.getCandleStickDataPoint(for: timestamp)?.close, serverPrice(interval))
                XCTAssertEqual(provider.getVolumeValueAndColor(for: timestamp)?.volume, Double(interval) * 123)
            }
            XCTAssertEqual(provider.technicalIndicators.count, 2)
            for indicator in provider.technicalIndicators {
                XCTAssertEqual(indicator.dataPoints.count, timestamps.count - 9)
                XCTAssertTrue(indicator.dataPoints.allSatisfy { abs($0.y - serverPrice(interval)) < 0.0001 })
            }
        }
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await provider.waitForPendingRequest()
        XCTAssertEqual(observations, [1, 5])
        withExtendedLifetime(observation) {}
    }

    func testCachedCoverageAndInFlightRequestsAreReusedButPanningFetchesMore() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        let initial = viewport(pointsPerMinute: 2)
        provider.updateViewport(initial)
        await waitForRequests(1, transport)
        for _ in 0..<4 { provider.updateViewport(initial) }
        provider.updateViewport(ChartViewport(visibleXRange: initial.visibleXRange, visibleYRange: 1...2, plotSize: initial.plotSize))
        provider.updateViewport(viewport(pointsPerMinute: 6.5))
        await assertRequestCount(1, transport)
        XCTAssertTrue(provider.isLoading)
        XCTAssertEqual(provider.requestedIntervalMinutes, 5, "Hysteresis must use the pending selection rather than bouncing back to displayed 1m data.")
        XCTAssertEqual(provider.candleIntervalMinutes, 1, "The label must describe displayed bars while a new level loads.")
        try await transport.succeed(0)
        await provider.waitForPendingRequest()

        provider.updateViewport(initial)
        provider.updateViewport(viewport(pointsPerMinute: 2, center: fixtureCenter + 10 * minute))
        await provider.waitForPendingRequest()
        await assertRequestCount(1, transport)

        provider.updateViewport(viewport(pointsPerMinute: 2, center: fixtureCenter - 3 * day))
        await waitForRequests(2, transport)
        try await transport.succeed(1)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        await assertRequestCount(2, transport)
    }

    func testRapidGesturesDebounceToTheFinalResolutionAndRange() async throws {
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport, debounce: 40_000_000)
        let distant = fixtureCenter - 3 * day
        provider.updateViewport(viewport(pointsPerMinute: 2, center: distant))
        provider.updateViewport(viewport(pointsPerMinute: 0.5, center: distant))
        let final = viewport(pointsPerMinute: 10, center: distant)
        provider.updateViewport(final)
        await provider.waitForPendingRequest()

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let info = try RequestInfo(try XCTUnwrap(requests.first))
        XCTAssertEqual(info.granularity, 60)
        XCTAssertLessThanOrEqual(try XCTUnwrap(info.start), final.visibleXRange.lowerBound)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(info.end), final.visibleXRange.upperBound)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
    }

    func testStaleSuccessCannotReplaceNewerDisplayedData() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await waitForRequests(1, transport)
        let oldWaiter = await capturePendingRequest(provider)
        provider.updateViewport(viewport(pointsPerMinute: 0.5))
        await waitForRequests(2, transport)
        try await transport.succeed(1)
        await provider.waitForPendingRequest()
        let timestamps = provider.getXValues(in: 0...Double.greatestFiniteMagnitude)
        XCTAssertEqual(provider.candleIntervalMinutes, 15)

        // This transport intentionally completes even though its task was cancelled.
        try await transport.succeed(0)
        await oldWaiter.value
        XCTAssertEqual(provider.candleIntervalMinutes, 15)
        XCTAssertEqual(provider.getXValues(in: 0...Double.greatestFiniteMagnitude), timestamps)
        XCTAssertFalse(provider.isLoading)
        XCTAssertNil(provider.errorMessage)
    }

    func testStaleFailureCannotClearNewRequestLoadingOrPublishAnError() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await waitForRequests(1, transport)
        let oldWaiter = await capturePendingRequest(provider)
        provider.updateViewport(viewport(pointsPerMinute: 0.5))
        await waitForRequests(2, transport)
        await transport.fail(0, error: URLError(.notConnectedToInternet))
        await oldWaiter.value

        XCTAssertTrue(provider.isLoading)
        XCTAssertEqual(provider.requestedIntervalMinutes, 15)
        XCTAssertNil(provider.errorMessage)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        try await transport.succeed(1)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 15)
        XCTAssertFalse(provider.isLoading)
    }

    func testStaleFailureCannotReplaceTheCurrentRequestError() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await waitForRequests(1, transport)
        let oldWaiter = await capturePendingRequest(provider)
        provider.updateViewport(viewport(pointsPerMinute: 0.5))
        await waitForRequests(2, transport)
        try await transport.succeed(1, status: 429)
        await provider.waitForPendingRequest()
        let currentError = try XCTUnwrap(provider.errorMessage)
        XCTAssertTrue(currentError.contains("429"))
        await transport.fail(0, error: URLError(.timedOut))
        await oldWaiter.value
        XCTAssertEqual(provider.errorMessage, currentError)
        XCTAssertFalse(provider.isLoading)
    }

    func testFailureKeepsDisplayedDataAndRevisionThenExplicitRetrySucceeds() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        let original = provider.getXValues(in: 0...Double.greatestFiniteMagnitude)
        let revision = provider.revision
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await waitForRequests(1, transport)
        try await transport.succeed(0, status: 503)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.getXValues(in: 0...Double.greatestFiniteMagnitude), original)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        XCTAssertEqual(provider.revision, revision)
        XCTAssertNotNil(provider.errorMessage)
        XCTAssertFalse(provider.isLoading)
        let failed = viewport(pointsPerMinute: 2)
        provider.updateViewport(ChartViewport(visibleXRange: failed.visibleXRange, visibleYRange: 1...2, plotSize: failed.plotSize))
        await provider.waitForPendingRequest()
        await assertRequestCount(1, transport)
        XCTAssertNotNil(provider.errorMessage, "A Y-only viewport change must not clear errors or repeatedly retry the same failed request.")

        let retry = Task { await provider.retryFailedLoad() }
        await waitForRequests(2, transport)
        try await transport.succeed(1)
        await retry.value
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        XCTAssertEqual(provider.revision, revision)
        XCTAssertNil(provider.errorMessage)
    }

    func testRefreshWinsOverPendingDetailAndInvalidatesOldCoverage() async throws {
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        let previousRevision = provider.revision
        let previousRange = try XCTUnwrap(provider.getInitDataRanges())
        let detailViewport = viewport(pointsPerMinute: 2)
        provider.updateViewport(detailViewport)
        await waitForRequests(1, transport)
        let oldWaiter = await capturePendingRequest(provider)
        let refresh = Task { await provider.refresh() }
        await waitForRequests(2, transport)
        try await transport.succeed(1)
        await refresh.value
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        XCTAssertNotEqual(provider.revision, previousRevision)
        XCTAssertNotEqual(provider.getInitDataRanges()?.chartXMin, previousRange.chartXMin)
        let newTimestamps = provider.getXValues(in: 0...Double.greatestFiniteMagnitude)
        try await transport.succeed(0)
        await oldWaiter.value
        XCTAssertEqual(provider.getXValues(in: 0...Double.greatestFiniteMagnitude), newTimestamps)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)

        provider.updateViewport(detailViewport)
        await waitForRequests(3, transport)
        try await transport.succeed(2)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        await assertRequestCount(3, transport)
    }

    func testRetryAfterRefreshFailureRequestsRecentCandles() async throws {
        let transport = AutomaticHistoryTransport(statuses: [503])
        let provider = makeProvider(transport: transport)
        provider.updateViewport(viewport(pointsPerMinute: 10))
        let revision = provider.revision

        await provider.refresh()
        XCTAssertNotNil(provider.errorMessage)
        XCTAssertEqual(provider.revision, revision)

        await provider.retryFailedLoad()

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let retried = try RequestInfo(try XCTUnwrap(requests.last))
        XCTAssertEqual(retried.granularity, 60)
        XCTAssertNil(retried.start)
        XCTAssertNil(retried.end)
        XCTAssertNotEqual(provider.revision, revision)
        XCTAssertFalse(provider.isSnapshot)
        XCTAssertFalse(provider.isLoading)
        XCTAssertNil(provider.errorMessage)
    }

    func testRetryAfterRefreshFailureWorksWithoutAnInitialViewport() async throws {
        let transport = AutomaticHistoryTransport(statuses: [503])
        let provider = BTCDataProvider(candles: [], fetchData: { request in
            try await transport.fetch(request)
        })
        await provider.refresh()
        XCTAssertNil(provider.getInitDataRanges())
        XCTAssertNotNil(provider.errorMessage)

        await provider.retryFailedLoad()

        await assertRequestCount(2, transport)
        XCTAssertNotNil(provider.getInitDataRanges())
        XCTAssertFalse(provider.isSnapshot)
        XCTAssertNil(provider.errorMessage)
    }

    func testRefreshFailureRetrySupersedesAnEarlierHistoryFailure() async throws {
        let transport = AutomaticHistoryTransport(statuses: [503, 429])
        let provider = makeProvider(transport: transport)
        provider.updateViewport(viewport(pointsPerMinute: 2))
        await provider.waitForPendingRequest()
        XCTAssertTrue(provider.errorMessage?.contains("503") == true)

        await provider.refresh()
        XCTAssertTrue(provider.errorMessage?.contains("429") == true)
        let revision = provider.revision
        await provider.retryFailedLoad()

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        let retried = try RequestInfo(try XCTUnwrap(requests.last))
        XCTAssertEqual(retried.granularity, 60)
        XCTAssertNil(retried.start)
        XCTAssertNil(retried.end)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        XCTAssertNotEqual(provider.revision, revision)
        XCTAssertNil(provider.errorMessage)
    }

    func testHysteresisAvoidsRepeatedFetchesAtDetailBoundaries() async throws {
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport)
        for spacing in [8.1, 7.9, 6.5, 6.41] {
            provider.updateViewport(viewport(pointsPerMinute: spacing))
            await provider.waitForPendingRequest()
            XCTAssertEqual(provider.candleIntervalMinutes, 1)
        }
        provider.updateViewport(viewport(pointsPerMinute: 6.3))
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        let count = await transport.requests.count
        for spacing in [6.5, 7.9, 8.1, 9.5] {
            provider.updateViewport(viewport(pointsPerMinute: spacing))
            await provider.waitForPendingRequest()
            XCTAssertEqual(provider.candleIntervalMinutes, 5)
        }
        await assertRequestCount(count, transport)
        provider.updateViewport(viewport(pointsPerMinute: 9.7))
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
    }

    func testPaginationBoundsFiltersDuplicatesAndPreservesGaps() async throws {
        let plan = try CoinbaseHistoryRequest(intervalMinutes: 1, visibleRange: fixtureStart...(fixtureStart + 1_200 * minute))
        XCTAssertGreaterThan(plan.pages.count, 1)
        for request in plan.pages {
            let info = try RequestInfo(request)
            let start = try XCTUnwrap(info.start)
            let end = try XCTUnwrap(info.end)
            XCTAssertEqual(info.granularity, 60)
            XCTAssertGreaterThan(end, start)
            XCTAssertLessThanOrEqual((end - start) / minute, 300)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
        let result = try await CoinbaseHistory.load(plan) { request in
            let info = try RequestInfo(request)
            let start = try XCTUnwrap(info.start)
            let end = try XCTUnwrap(info.end)
            // Coinbase may return out-of-range candles or overlapping page data.
            let times = [end, start + 2 * minute, start, start, start - minute]
            return try response(request, timestamps: times, interval: 1)
        }
        let expected = try plan.pages.flatMap { request -> [Double] in
            let start = try XCTUnwrap(RequestInfo(request).start)
            return [start, start + 2 * minute]
        }.filter { plan.coveredRange.contains($0) }.sorted()
        XCTAssertEqual(result.map(\.timestamp), expected)
        XCTAssertEqual(Set(result.map(\.timestamp)).count, result.count)
        XCTAssertFalse(result.contains { $0.timestamp == expected[0] + minute }, "Missing trading intervals must stay missing.")
    }

    func testLiveEdgeCacheExpiresWhileHistoricalCoverageRemainsReusable() async throws {
        let transport = AutomaticHistoryTransport()
        var now = Date(timeIntervalSince1970: fixtureCenter / 1_000)
        let provider = BTCDataProvider(
            candles: fixtureHistory(), debounceNanoseconds: 0, now: { now },
            fetchData: { try await transport.fetch($0) }
        )
        let recent = viewport(pointsPerMinute: 2)
        provider.updateViewport(recent)
        await provider.waitForPendingRequest()
        await assertRequestCount(1, transport)
        now = now.addingTimeInterval(59)
        provider.updateViewport(recent)
        await provider.waitForPendingRequest()
        await assertRequestCount(1, transport)
        now = now.addingTimeInterval(2)
        provider.updateViewport(recent)
        await provider.waitForPendingRequest()
        await assertRequestCount(2, transport)

        let historical = viewport(pointsPerMinute: 2, center: fixtureCenter - 7 * day)
        provider.updateViewport(historical)
        await provider.waitForPendingRequest()
        await assertRequestCount(3, transport)
        now = now.addingTimeInterval(24 * 60 * 60)
        provider.updateViewport(historical)
        await provider.waitForPendingRequest()
        await assertRequestCount(3, transport)
    }

    func testHistoryCoverageExcludesItsEndAndRejectsWrongBucketAlignment() async throws {
        let plan = try CoinbaseHistoryRequest(intervalMinutes: 5, visibleRange: viewport(pointsPerMinute: 2).visibleXRange)
        XCTAssertFalse(plan.covers(plan.coveredRange, interval: 5), "The unqueried end timestamp cannot count as cached data.")
        let inside = plan.coveredRange.lowerBound...(plan.coveredRange.upperBound - 5 * minute)
        XCTAssertTrue(plan.covers(inside, interval: 5))
        do {
            _ = try await CoinbaseHistory.load(plan) { request in
                let start = try XCTUnwrap(RequestInfo(request).start)
                return try response(request, timestamps: [start + minute], interval: 5)
            }
            XCTFail("A five-minute response must not accept a one-minute-aligned bucket.")
        } catch {}
        XCTAssertThrowsError(try CoinbaseHistoryRequest(intervalMinutes: 2, visibleRange: inside))
        XCTAssertThrowsError(try CoinbaseHistoryRequest(intervalMinutes: 1, visibleRange: fixtureStart...(fixtureStart + 365 * day)))
    }

    func testEmptyHistoryPagesAreAllowedButNoDataIsAnError() async throws {
        let plan = try CoinbaseHistoryRequest(intervalMinutes: 1, visibleRange: fixtureStart...(fixtureStart + 600 * minute))
        let firstURL = plan.pages[0].url
        let result = try await CoinbaseHistory.load(plan) { request in
            if request.url == firstURL {
                return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let info = try RequestInfo(request)
            return try response(request, timestamps: [try XCTUnwrap(info.start)], interval: 1)
        }
        XCTAssertEqual(result.count, plan.pages.count - 1)
        do {
            _ = try await CoinbaseHistory.load(plan) { request in
                (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("An entirely empty server response must not erase displayed data.")
        } catch {}
    }

    func testNativeChartResponsePreservesViewportAndInitialResetAnchor() async throws {
        #if !canImport(UIKit)
        _ = NSApplication.shared
        #endif
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        let originalRanges = try XCTUnwrap(provider.getInitDataRanges())
        let chart = InfiniteChartBase(
            frame: CGRect(x: 0, y: 0, width: 800, height: 400), dataProvider: provider,
            xAxisConfig: AxisConfig(requiredSpace: 30), yAxisConfig: AxisConfig(requiredSpace: 40)
        )
        let initial = expectation(description: "Initial viewport")
        let initialObservation = chart.viewportStream.compactMap { $0 }.prefix(1).sink { _ in initial.fulfill() }
        #if canImport(UIKit)
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        #else
        chart.needsLayout = true
        chart.layoutSubtreeIfNeeded()
        #endif
        await fulfillment(of: [initial], timeout: 2)
        initialObservation.cancel()
        let viewportObservation = chart.viewportStream.compactMap { $0 }.sink { viewport in provider.updateViewport(viewport) }
        chart.setVisibleXRange((fixtureCenter - 200 * minute)...(fixtureCenter + 200 * minute))
        let requested = try XCTUnwrap(chart.viewportStream.value)
        await waitForRequests(1, transport)
        try await transport.succeed(0)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        XCTAssertEqual(chart.viewportStream.value, requested, "Receiving remote bars alone must preserve both X and Y ranges.")
        assertSameRanges(try XCTUnwrap(provider.getInitDataRanges()), originalRanges)
        viewportObservation.cancel()
        chart.resetViewport()
        let reset = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(reset.visibleXRange.lowerBound, originalRanges.chartXMin, accuracy: 0.001)
        XCTAssertEqual(reset.visibleXRange.upperBound, originalRanges.chartXMin + originalRanges.deltaX, accuracy: 0.001)
        XCTAssertEqual(reset.visibleYRange.lowerBound, originalRanges.chartYMin, accuracy: 0.001)
    }

    func testHorizontalOnlyChartControlsFitPricesAfterLatestHorizontalNavigation() async throws {
        #if !canImport(UIKit)
        _ = NSApplication.shared
        #endif
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport)
        let chart = InfiniteChartBase(
            frame: CGRect(x: 0, y: 0, width: 800, height: 400), dataProvider: provider,
            xAxisConfig: AxisConfig(requiredSpace: 30), yAxisConfig: AxisConfig(requiredSpace: 40)
        )
        chart.transformableAxes = [.horizontal]
        #if canImport(UIKit)
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        #else
        chart.needsLayout = true
        chart.layoutSubtreeIfNeeded()
        #endif
        chart.setVisibleYRange(0...1_000)
        let originalYRange = try XCTUnwrap(chart.viewportStream.value).visibleYRange
        let requestedRange = (fixtureCenter - 20 * minute)...(fixtureCenter + 20 * minute)
        let priceRange = try XCTUnwrap(provider.priceRange(in: requestedRange))
        let controls = BTCChartControls()
        let fitted = expectation(description: "Visible prices fitted after horizontal navigation")
        let fitObservation = chart.viewportStream
            .compactMap { $0 }
            .filter { abs($0.visibleYRange.lowerBound - priceRange.lowerBound) < 0.001 }
            .prefix(1)
            .sink { _ in fitted.fulfill() }
        let spanUpdated = expectation(description: "Visible span published after attachment")
        let spanObservation = controls.$visibleSpanText
            .filter { $0 == "Viewing 40m · UTC" }
            .prefix(1)
            .sink { _ in spanUpdated.fulfill() }
        defer { withExtendedLifetime((controls, fitObservation, spanObservation)) {} }

        controls.attach(chart, provider: provider)
        chart.setVisibleXRange((fixtureCenter - 200 * minute)...(fixtureCenter + 200 * minute))
        chart.setVisibleXRange(requestedRange)
        let completedXRange = try XCTUnwrap(chart.viewportStream.value).visibleXRange
        XCTAssertEqual(completedXRange.lowerBound, requestedRange.lowerBound, accuracy: 0.001)
        XCTAssertEqual(completedXRange.upperBound, requestedRange.upperBound, accuracy: 0.001)
        XCTAssertEqual(chart.viewportStream.value?.visibleYRange, originalYRange, "Price fitting must wait for navigation to finish.")
        XCTAssertEqual(controls.visibleSpanText, "Preparing chart…", "Attachment must defer SwiftUI state changes.")

        await fulfillment(of: [fitted, spanUpdated], timeout: 2)
        let viewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(viewport.visibleXRange, completedXRange, "Automatic price fitting must preserve the latest horizontal range exactly.")
        XCTAssertEqual(viewport.visibleYRange.lowerBound, priceRange.lowerBound, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleYRange.upperBound, priceRange.upperBound, accuracy: 0.001)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        await assertRequestCount(0, transport)
    }

    func testHorizontalOnlyChartControlsRefitRemotePricesWithoutRedrawLoop() async throws {
        #if !canImport(UIKit)
        _ = NSApplication.shared
        #endif
        let transport = ControlledHistoryTransport()
        let provider = makeProvider(transport: transport)
        let chart = InfiniteChartBase(
            frame: CGRect(x: 0, y: 0, width: 800, height: 400), dataProvider: provider,
            xAxisConfig: AxisConfig(requiredSpace: 30), yAxisConfig: AxisConfig(requiredSpace: 40)
        )
        chart.transformableAxes = [.horizontal]
        #if canImport(UIKit)
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        #else
        chart.needsLayout = true
        chart.layoutSubtreeIfNeeded()
        #endif
        chart.setVisibleYRange(50...250)
        let controls = BTCChartControls()
        controls.attach(chart, provider: provider)
        chart.setVisibleXRange((fixtureCenter - 200 * minute)...(fixtureCenter + 200 * minute))
        let navigatedViewport = try XCTUnwrap(chart.viewportStream.value)

        await waitForRequests(1, transport)
        try await transport.succeed(0)
        await provider.waitForPendingRequest()
        XCTAssertEqual(provider.candleIntervalMinutes, 5)
        let priceRange = try XCTUnwrap(provider.priceRange(in: navigatedViewport.visibleXRange))
        let fitted = expectation(description: "Price axis fitted to fetched five-minute candles")
        let fitObservation = chart.viewportStream
            .compactMap { $0 }
            .filter { abs($0.visibleYRange.lowerBound - priceRange.lowerBound) < 0.001 }
            .prefix(1)
            .sink { _ in fitted.fulfill() }
        await fulfillment(of: [fitted], timeout: 2)

        let fittedViewport = try XCTUnwrap(chart.viewportStream.value)
        XCTAssertEqual(fittedViewport.visibleXRange, navigatedViewport.visibleXRange,
                       "Replacing detail and fitting prices must preserve the horizontal range exactly.")
        XCTAssertEqual(fittedViewport.visibleYRange.lowerBound, priceRange.lowerBound, accuracy: 0.001)
        XCTAssertEqual(fittedViewport.visibleYRange.upperBound, priceRange.upperBound, accuracy: 0.001)

        let unchanged = expectation(description: "Indicator redraw must not emit another viewport")
        unchanged.isInverted = true
        let observation = chart.viewportStream.dropFirst().sink { _ in unchanged.fulfill() }
        defer { withExtendedLifetime((controls, fitObservation, observation)) {} }
        provider.showingEMA = true
        await fulfillment(of: [unchanged], timeout: 0.1)

        XCTAssertEqual(chart.viewportStream.value, fittedViewport)
        await assertRequestCount(1, transport)
    }

    func testInvalidViewportsDoNotRequestRemoteData() async {
        let transport = AutomaticHistoryTransport()
        let provider = makeProvider(transport: transport)
        let invalid = [
            ChartViewport(visibleXRange: 0...0, visibleYRange: 0...1, plotSize: CGSize(width: 800, height: 400)),
            ChartViewport(visibleXRange: 0...Double.infinity, visibleYRange: 0...1, plotSize: CGSize(width: 800, height: 400)),
            ChartViewport(visibleXRange: fixtureStart...(fixtureStart + minute), visibleYRange: 0...1, plotSize: .zero),
            ChartViewport(visibleXRange: fixtureStart...(fixtureStart + minute), visibleYRange: 0...1, plotSize: CGSize(width: Double.infinity, height: 400)),
        ]
        for viewport in invalid { provider.updateViewport(viewport) }
        await provider.waitForPendingRequest()
        await assertRequestCount(0, transport)
        XCTAssertEqual(provider.candleIntervalMinutes, 1)
        XCTAssertFalse(provider.isLoading)
    }

    func testIndexedLookupHonorsInclusiveRangeWithoutInventingSamples() {
        let provider = BTCDataProvider(candles: [0, 2, 5, 8].map { fixtureCandle(timestamp: fixtureStart + Double($0) * minute) })
        XCTAssertEqual(provider.getXValues(in: (fixtureStart + 2 * minute)...(fixtureStart + 5 * minute)), [fixtureStart + 2 * minute, fixtureStart + 5 * minute])
        XCTAssertEqual(provider.getXValues(in: (fixtureStart + 3 * minute)...(fixtureStart + 4 * minute)), [])
        XCTAssertEqual(provider.getXValues(in: (fixtureStart - 2 * minute)...(fixtureStart - minute)), [])
    }

    private func makeProvider(transport: AutomaticHistoryTransport, debounce: UInt64 = 0) -> BTCDataProvider {
        BTCDataProvider(candles: fixtureHistory(), visibleCandleCount: 60, debounceNanoseconds: debounce, fetchData: { request in
            try await transport.fetch(request)
        })
    }

    private func makeProvider(transport: ControlledHistoryTransport) -> BTCDataProvider {
        BTCDataProvider(candles: fixtureHistory(), visibleCandleCount: 60, debounceNanoseconds: 0, fetchData: { request in
            try await transport.fetch(request)
        })
    }

    private func assertRequestCount(_ count: Int, _ transport: ControlledHistoryTransport, file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await transport.requestCount
        XCTAssertEqual(actual, count, file: file, line: line)
    }

    private func assertRequestCount(_ count: Int, _ transport: AutomaticHistoryTransport, file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await transport.requests.count
        XCTAssertEqual(actual, count, file: file, line: line)
    }

    private func waitForRequests(_ count: Int, _ transport: ControlledHistoryTransport, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await transport.requestCount >= count { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Expected \(count) transport requests", file: file, line: line)
    }

    private func capturePendingRequest(_ provider: BTCDataProvider) async -> Task<Void, Never> {
        let started = expectation(description: "Await superseded task")
        let waiter = Task {
            started.fulfill()
            await provider.waitForPendingRequest()
        }
        await fulfillment(of: [started], timeout: 2)
        return waiter
    }
}

private let minute = 60_000.0
private let day = 24 * 60 * minute
private let fixtureStart = 1_724_587_200_000.0
private let fixtureCenter = fixtureStart + 120 * minute

private func fixtureCandle(timestamp: Double) -> BTCCandle {
    BTCCandle(timestamp: timestamp, low: 98, high: 104, open: 100, close: 102, volume: 1)
}

private func fixtureHistory() -> [BTCCandle] {
    (0..<240).map { fixtureCandle(timestamp: fixtureStart + Double($0) * minute) }
}

private func viewport(pointsPerMinute: Double, center: Double = fixtureCenter) -> ChartViewport {
    let span = 800 * minute / pointsPerMinute
    return ChartViewport(visibleXRange: (center - span / 2)...(center + span / 2), visibleYRange: 90...120, plotSize: CGSize(width: 800, height: 400))
}

private func serverPrice(_ interval: Int) -> Double { 10_000 + Double(interval) * 100 }

private func assertSameRanges(_ actual: DataRanges, _ expected: DataRanges, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.chartXMin, expected.chartXMin, file: file, line: line)
    XCTAssertEqual(actual.chartYMin, expected.chartYMin, file: file, line: line)
    XCTAssertEqual(actual.deltaX, expected.deltaX, file: file, line: line)
    XCTAssertEqual(actual.deltaY, expected.deltaY, file: file, line: line)
}

private struct RequestInfo {
    let granularity: Int
    let start: Double?
    let end: Double?

    init(_ request: URLRequest) throws {
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "api.exchange.coinbase.com")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        granularity = try XCTUnwrap(query["granularity"].flatMap(Int.init))
        func milliseconds(_ value: String?) throws -> Double? {
            guard let value else { return nil }
            if let seconds = Double(value) { return seconds * 1_000 }
            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: value)
            formatter.formatOptions.insert(.withFractionalSeconds)
            return try XCTUnwrap(date ?? formatter.date(from: value)).timeIntervalSince1970 * 1_000
        }
        start = try milliseconds(query["start"])
        end = try milliseconds(query["end"])
    }
}

private func response(_ request: URLRequest, timestamps: [Double]? = nil, interval: Int? = nil, status: Int = 200) throws -> (Data, URLResponse) {
    let info = try RequestInfo(request)
    let selectedInterval = interval ?? info.granularity / 60
    let step = Double(selectedInterval) * minute
    let start = info.start ?? fixtureStart + 10 * day
    let end = info.end ?? start + 240 * step
    let times = timestamps ?? Array(stride(from: start, to: end, by: step))
    let price = serverPrice(selectedInterval)
    let rows = times.reversed().map { [$0 / 1_000, price - 5, price + 5, price - 2, price, Double(selectedInterval) * 123] }
    return (
        try JSONSerialization.data(withJSONObject: rows),
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
}

private actor AutomaticHistoryTransport {
    private(set) var requests: [URLRequest] = []
    private let statuses: [Int]

    init(statuses: [Int] = []) {
        self.statuses = statuses
    }

    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        let status = requests.count < statuses.count ? statuses[requests.count] : 200
        requests.append(request)
        return try response(request, status: status)
    }
}

/// Deliberately ignores task cancellation so generation checks face late responses.
private actor ControlledHistoryTransport {
    private var requests: [URLRequest] = []
    private var continuations: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    var requestCount: Int { requests.count }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let index = requests.count
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func succeed(_ index: Int, status: Int = 200) throws {
        let result = try response(requests[index], status: status)
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }

    func fail(_ index: Int, error: Error) {
        continuations.removeValue(forKey: index)?.resume(throwing: error)
    }
}
