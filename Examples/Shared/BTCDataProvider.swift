import Combine
import Foundation
import InfiniteChart

/// Shared by both native examples. Read and modify the provider on the main thread.
/// The chart protocols are not actor isolated; navigation and network publication run on the main actor.
public final class BTCDataProvider: ObservableObject, CandleStickDataProvider, VolumeDataProvider, LineChartDataProvider, IndexedChartDataProvider {
    @Published public var showingSMA = true {
        didSet { if showingSMA != oldValue { redraw.send(()) } }
    }
    @Published public var showingEMA = false {
        didSet { if showingEMA != oldValue { redraw.send(()) } }
    }
    @Published public private(set) var isLoading = false
    @Published public private(set) var statusText = "Bundled historical snapshot"
    @Published public private(set) var errorMessage: String?
    /// Changes only when source data is replaced, allowing SwiftUI to reset the viewport after refresh.
    @Published public private(set) var revision = UUID()
    @Published public private(set) var isSnapshot = true
    /// The example application selects this interval from the chart's viewport.
    @Published public private(set) var candleIntervalMinutes = 1
    /// The requested interval while loading. The displayed interval changes only after a successful response.
    @Published public private(set) var requestedIntervalMinutes: Int?

    public weak var tranformerUpdatedDelegate: (any ChartDataProviderDelegate)?
    public var redrawStream: AnyPublisher<Void, Never> { redraw.eraseToAnyPublisher() }

    private let redraw = CurrentValueSubject<Void, Never>(())
    private var initialCandles: [BTCCandle] = []
    private var historyCache: [BTCHistorySnapshot] = []
    private var displayedSnapshotID: UUID?
    private var detail = BTCDetailData(candles: [])
    private var candles: [BTCCandle] { detail.candles }
    private var candlesByTime: [Double: BTCCandle] { detail.candlesByTime }
    private let visibleCandleCount: Int
    private let debounceNanoseconds: UInt64
    private let now: () -> Date
    private let fetchData: (URLRequest) async throws -> (Data, URLResponse)
    private var loadTask: Task<Void, Never>?
    private var requestGeneration = UUID()
    private var pendingRequest: CoinbaseHistoryRequest?
    private var lastViewport: ChartViewport?
    private var selectionIntervalMinutes = 1
    private var isRefreshing = false
    private var failedViewportRange: ClosedRange<Double>?
    private var failedIntervalMinutes: Int?

    public convenience init(visibleCandleCount: Int = 120) {
        self.init(candles: [], visibleCandleCount: visibleCandleCount)
        do {
            guard let url = Bundle.module.url(forResource: "btc-usd-1m", withExtension: "json") else {
                throw BTCCandleError.missingSnapshot
            }
            replaceInitialCandles(try CoinbaseCandles.decode(Data(contentsOf: url)), isBundled: true)
        } catch {
            statusText = "Snapshot unavailable"
            errorMessage = error.localizedDescription
        }
    }

    // A deterministic input and transport make the sample testable without a network connection.
    init(
        candles: [BTCCandle],
        visibleCandleCount: Int = 120,
        debounceNanoseconds: UInt64 = 250_000_000,
        now: @escaping () -> Date = Date.init,
        fetchData: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.visibleCandleCount = max(1, visibleCandleCount)
        self.debounceNanoseconds = debounceNanoseconds
        self.now = now
        self.fetchData = fetchData
        replaceInitialCandles(candles, isBundled: true)
    }

    deinit { loadTask?.cancel() }

    public var latestPriceText: String {
        guard let last = candles.last else { return "—" }
        return Self.currency(last.close)
    }

    /// This is the change over all loaded candles, not a rolling 24-hour quote.
    public var changeText: String {
        guard let first = candles.first, let last = candles.last else { return "No price data" }
        let change = last.close - first.open
        let sign = change >= 0 ? "+" : "−"
        let percent = abs(change / first.open * 100)
        return "\(sign)\(Self.currency(abs(change))) (\(sign)\(String(format: "%.2f", percent))%) over loaded period"
    }

    public var isPriceUp: Bool {
        guard let first = candles.first, let last = candles.last else { return true }
        return last.close >= first.open
    }

    public var sourceText: String {
        isSnapshot ? "Coinbase Exchange · bundled historical snapshot" : "Coinbase Exchange · fetched on demand"
    }

    public var rangeText: String {
        guard let first = candles.first, let last = candles.last else { return "No candles loaded" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy HH:mm"
        let start = formatter.string(from: Date(timeIntervalSince1970: first.timestamp / 1_000))
        let end = formatter.string(from: Date(timeIntervalSince1970: last.timestamp / 1_000))
        let interval = candleIntervalMinutes == 1 ? "one-minute" : "\(candleIntervalMinutes)-minute"
        return "\(start) – \(end) UTC · \(candles.count) \(interval) candles"
    }

    public var detailText: String { "\(candleIntervalMinutes)-minute candles" }

    /// Nominal bucket width in the timestamp unit used by this example: milliseconds.
    public var nominalXStep: Double { Double(candleIntervalMinutes) * 60_000 }

    /// Application policy: request Coinbase's 1m, 5m, or 15m history for roughly eight points per bar.
    /// Fetching is debounced and range-aware; a 20% margin prevents repeated resolution changes.
    /// Existing data stays visible while loading, and successful replacements preserve the viewport.
    @MainActor public func updateViewport(_ viewport: ChartViewport) {
        let span = viewport.visibleXRange.upperBound - viewport.visibleXRange.lowerBound
        let width = Double(viewport.plotSize.width)
        guard viewport.visibleXRange.lowerBound.isFinite, span.isFinite, span > 0, width.isFinite, width > 0 else { return }
        lastViewport = viewport
        guard !isRefreshing else { return }
        let pointsPerMinute = 60_000 / span * width
        let intervals = [1, 5, 15]
        let targetSpacing = 8.0
        let margin = 0.2
        let selected: Int
        if pointsPerMinute * Double(selectionIntervalMinutes) < targetSpacing * (1 - margin) {
            selected = intervals.first { pointsPerMinute * Double($0) >= targetSpacing } ?? 15
        } else {
            selected = intervals.first {
                $0 < selectionIntervalMinutes && pointsPerMinute * Double($0) >= targetSpacing * (1 + margin)
            } ?? selectionIntervalMinutes
        }
        selectionIntervalMinutes = selected
        if let index = historyCache.firstIndex(where: { $0.covers(viewport.visibleXRange, interval: selected) && $0.isFresh(at: now()) }) {
            let cached = historyCache.remove(at: index)
            historyCache.insert(cached, at: 0)
            if pendingRequest != nil { cancelPendingLoad() }
            errorMessage = nil
            failedViewportRange = nil
            failedIntervalMinutes = nil
            statusText = cached.isBundled ? "Bundled historical snapshot" : "Cached \(selected)-minute Coinbase history"
            guard displayedSnapshotID != cached.id else { return }
            display(cached)
            return
        }
        if pendingRequest?.covers(viewport.visibleXRange, interval: selected) == true { return }
        if failedIntervalMinutes == selected, failedViewportRange == viewport.visibleXRange { return }
        scheduleLoad(interval: selected, range: viewport.visibleXRange)
    }

    /// Retries the current historical viewport rather than jumping to the latest market data.
    @MainActor public func retryViewportLoad() {
        guard let lastViewport, !isRefreshing else { return }
        cancelPendingLoad()
        failedViewportRange = nil
        failedIntervalMinutes = nil
        updateViewport(lastViewport)
    }

    /// Deterministic test seam: waits for the task that was pending when this method was called.
    @MainActor func waitForPendingRequest() async {
        await loadTask?.value
    }

    /// Padded price bounds for candles whose time buckets intersect the visible range.
    public func priceRange(in range: ClosedRange<Double>) -> ClosedRange<Double>? {
        let visible = candles.filter { $0.timestamp <= range.upperBound && $0.timestamp + nominalXStep > range.lowerBound }
        guard let low = visible.map(\.low).min(), let high = visible.map(\.high).max() else { return nil }
        let padding = max((high - low) * 0.12, high * 0.001, 1)
        return (low - padding)...(high + padding)
    }

    /// Returns real bucket timestamps inside the requested inclusive range.
    /// Gaps stay empty; all OHLCV values come from Coinbase at the displayed granularity.
    public func getXValues(in range: ClosedRange<Double>) -> [Double] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, !candles.isEmpty else { return [] }
        let lower = insertionIndex(for: range.lowerBound)
        var upper = insertionIndex(for: range.upperBound)
        if upper < candles.count, candles[upper].timestamp == range.upperBound { upper += 1 }
        return candles[lower..<upper].map(\.timestamp)
    }

    public var technicalIndicators: [TechnicalIndicator] {
        var result: [TechnicalIndicator] = []
        if showingSMA { result.append(TechnicalIndicator(name: "SMA(10)", color: .systemBlue, dataPoints: detail.sma)) }
        if showingEMA { result.append(TechnicalIndicator(name: "EMA(10)", color: .systemPurple, dataPoints: detail.ema)) }
        return result
    }

    /// Requests the latest available minute candles once. No key or account is required.
    /// A failed request keeps the previously displayed candles and exposes its error to the UI.
    @MainActor public func refresh() async {
        guard !isRefreshing else { return }
        cancelPendingLoad()
        let generation = requestGeneration
        isRefreshing = true
        isLoading = true
        requestedIntervalMinutes = 1
        errorMessage = nil
        statusText = "Fetching recent candles…"
        do {
            let url = URL(string: "https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=60")!
            let (data, response) = try await fetchData(CoinbaseHistory.request(url: url))
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            try CoinbaseHistory.validate(response)
            let newCandles = try CoinbaseCandles.decode(data)
            replaceInitialCandles(newCandles, isBundled: false)
            lastViewport = nil
            statusText = "Fetched recent candles · newest candle may still be forming"
        } catch {
            guard requestGeneration == generation else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                statusText = isSnapshot ? "Bundled historical snapshot" : "Previously fetched candles"
            } else {
                errorMessage = error.localizedDescription
                statusText = candles.isEmpty ? "No candles available" : "Refresh failed · keeping displayed candles"
            }
        }
        guard requestGeneration == generation else { return }
        isRefreshing = false
        isLoading = false
        requestedIntervalMinutes = nil
    }

    public func getYValue(for xValue: Double) -> Double? { candlesByTime[xValue]?.close }

    public func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint? {
        guard let candle = candlesByTime[xValue] else { return nil }
        return CandleStickDataPoint(
            high: candle.high, low: candle.low, open: candle.open, close: candle.close,
            color: Self.color(for: candle)
        )
    }

    public func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)? {
        guard let candle = candlesByTime[xValue] else { return nil }
        return (volume: candle.volume, color: Self.color(for: candle))
    }

    public func getInitDataRanges() -> DataRanges? {
        // Keep candles readable on a phone; the earlier loaded history can be reached by panning.
        let visible = initialCandles.suffix(visibleCandleCount)
        guard let first = visible.first, let last = visible.last,
              let low = visible.map(\.low).min(), let high = visible.map(\.high).max() else { return nil }
        let padding = max((high - low) * 0.12, high * 0.001, 1)
        let minute = 60_000.0
        return DataRanges(
            chartXMin: first.timestamp - minute,
            deltaX: max(last.timestamp - first.timestamp, minute) + minute * 3,
            chartYMin: low - padding,
            deltaY: high - low + padding * 2
        )
    }

    /// Floor/ceiling lookup with an additional outward offset, clamped to available candles.
    public func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double? {
        guard !candles.isEmpty, xValue.isFinite else { return nil }
        let lower = insertionIndex(for: xValue)
        let distance = min(max(offset, 0), candles.count - 1)
        let base: Int
        if seekBelow {
            base = lower < candles.count && candles[lower].timestamp == xValue ? lower : lower - 1
            return candles[max(0, min(base, candles.count - 1) - distance)].timestamp
        } else {
            base = min(lower, candles.count - 1)
            return candles[min(candles.count - 1, base + distance)].timestamp
        }
    }

    private func replaceInitialCandles(_ candles: [BTCCandle], isBundled: Bool) {
        initialCandles = candles.sorted { $0.timestamp < $1.timestamp }
        historyCache = []
        selectionIntervalMinutes = 1
        failedViewportRange = nil
        failedIntervalMinutes = nil
        if let first = initialCandles.first, let last = initialCandles.last {
            // Include the chart's small leading/trailing padding without inventing history.
            let snapshot = BTCHistorySnapshot(
                intervalMinutes: 1, coveredRange: (first.timestamp - 60_000)...(last.timestamp + 180_000),
                data: BTCDetailData(candles: initialCandles), isBundled: isBundled, fetchedAt: now()
            )
            historyCache = [snapshot]
            display(snapshot, notify: false)
        } else {
            detail = BTCDetailData(candles: [])
            displayedSnapshotID = nil
            candleIntervalMinutes = 1
            isSnapshot = isBundled
        }
        revision = UUID()
        redraw.send(())
    }

    /// Publishes one immutable set of candles, volume, and derived indicators.
    private func display(_ snapshot: BTCHistorySnapshot, notify: Bool = true) {
        detail = snapshot.data
        displayedSnapshotID = snapshot.id
        isSnapshot = snapshot.isBundled
        candleIntervalMinutes = snapshot.intervalMinutes
        if notify { redraw.send(()) }
    }

    @MainActor private func cancelPendingLoad() {
        requestGeneration = UUID()
        loadTask?.cancel()
        loadTask = nil
        pendingRequest = nil
        requestedIntervalMinutes = nil
        isLoading = false
    }

    @MainActor private func scheduleLoad(interval: Int, range: ClosedRange<Double>) {
        cancelPendingLoad()
        failedViewportRange = nil
        failedIntervalMinutes = nil
        let plan: CoinbaseHistoryRequest
        do {
            plan = try CoinbaseHistoryRequest(intervalMinutes: interval, visibleRange: range)
        } catch {
            errorMessage = error.localizedDescription
            statusText = "History unavailable · keeping displayed candles"
            failedViewportRange = range
            failedIntervalMinutes = interval
            return
        }
        let generation = requestGeneration
        pendingRequest = plan
        requestedIntervalMinutes = interval
        errorMessage = nil
        isLoading = true
        statusText = "Loading \(interval)-minute history · keeping displayed candles"
        let delay = debounceNanoseconds
        let transport = fetchData
        loadTask = Task { @MainActor [weak self] in
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                try Task.checkCancellation()
                let candles = try await CoinbaseHistory.load(plan, fetchData: transport)
                try Task.checkCancellation()
                guard let self, self.requestGeneration == generation else { return }
                let snapshot = BTCHistorySnapshot(
                    intervalMinutes: interval, coveredRange: plan.coveredRange,
                    data: BTCDetailData(candles: candles), isBundled: false, fetchedAt: self.now()
                )
                self.historyCache.insert(snapshot, at: 0)
                if self.historyCache.count > 6 { self.historyCache.removeLast(self.historyCache.count - 6) }
                self.pendingRequest = nil
                self.requestedIntervalMinutes = nil
                self.isLoading = false
                self.loadTask = nil
                self.statusText = "Fetched \(interval)-minute Coinbase history"
                self.display(snapshot)
            } catch {
                guard let self, self.requestGeneration == generation else { return }
                self.pendingRequest = nil
                self.requestedIntervalMinutes = nil
                self.isLoading = false
                self.loadTask = nil
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.statusText = self.isSnapshot ? "Bundled historical snapshot" : "Previously fetched candles"
                } else {
                    self.errorMessage = error.localizedDescription
                    self.statusText = "History failed · keeping displayed candles"
                    self.failedViewportRange = self.lastViewport?.visibleXRange
                    self.failedIntervalMinutes = interval
                }
            }
        }
    }

    private func insertionIndex(for xValue: Double) -> Int {
        var lower = 0
        var upper = candles.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if candles[middle].timestamp < xValue { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    private static func color(for candle: BTCCandle) -> ChartColor {
        candle.close >= candle.open ? .systemGreen : .systemRed
    }

    private static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
