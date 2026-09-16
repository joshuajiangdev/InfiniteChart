import Combine
import Foundation
import InfiniteChart

/// Shared by both native examples. Read and modify the provider on the main thread.
/// The chart protocols are not actor isolated, so only the async refresh is annotated.
public final class BTCDataProvider: ObservableObject, CandleStickDataProvider, VolumeDataProvider, LineChartDataProvider {
    @Published public var showingSMA = true {
        didSet { if showingSMA != oldValue { redraw.send(()) } }
    }
    @Published public var showingEMA = false {
        didSet { if showingEMA != oldValue { redraw.send(()) } }
    }
    @Published public private(set) var isLoading = false
    @Published public private(set) var statusText = "Bundled historical snapshot"
    @Published public private(set) var errorMessage: String?
    /// Changes when candles change, allowing SwiftUI to reset the chart's cached viewport.
    @Published public private(set) var revision = UUID()
    @Published public private(set) var isSnapshot = true

    public weak var tranformerUpdatedDelegate: (any ChartDataProviderDelegate)?
    public var redrawStream: AnyPublisher<Void, Never> { redraw.eraseToAnyPublisher() }

    private let redraw = CurrentValueSubject<Void, Never>(())
    private var candles: [BTCCandle] = []
    private var candlesByTime: [Double: BTCCandle] = [:]
    private var sma: [(x: Double, y: Double)] = []
    private var ema: [(x: Double, y: Double)] = []
    private let visibleCandleCount: Int
    private let fetchData: (URLRequest) async throws -> (Data, URLResponse)

    public convenience init(visibleCandleCount: Int = 120) {
        self.init(candles: [], visibleCandleCount: visibleCandleCount)
        do {
            guard let url = Bundle.module.url(forResource: "btc-usd-1m", withExtension: "json") else {
                throw BTCCandleError.missingSnapshot
            }
            replaceCandles(try CoinbaseCandles.decode(Data(contentsOf: url)))
        } catch {
            statusText = "Snapshot unavailable"
            errorMessage = error.localizedDescription
        }
    }

    // A deterministic input and transport make the sample testable without a network connection.
    init(
        candles: [BTCCandle],
        visibleCandleCount: Int = 120,
        fetchData: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.visibleCandleCount = max(1, visibleCandleCount)
        self.fetchData = fetchData
        replaceCandles(candles)
    }

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
        return "\(start) – \(end) UTC · \(candles.count) one-minute candles"
    }

    public var technicalIndicators: [TechnicalIndicator] {
        var result: [TechnicalIndicator] = []
        if showingSMA { result.append(TechnicalIndicator(name: "SMA(10)", color: .systemBlue, dataPoints: sma)) }
        if showingEMA { result.append(TechnicalIndicator(name: "EMA(10)", color: .systemPurple, dataPoints: ema)) }
        return result
    }

    /// Requests the latest available minute candles once. No key or account is required.
    /// A failed request keeps the previously displayed candles and exposes its error to the UI.
    @MainActor public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        statusText = "Fetching recent candles…"
        defer { isLoading = false }
        do {
            let url = URL(string: "https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=60")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await fetchData(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw BTCCandleError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw BTCCandleError.httpStatus(response.statusCode) }
            let newCandles = try CoinbaseCandles.decode(data)
            isSnapshot = false
            replaceCandles(newCandles)
            statusText = "Fetched recent candles · newest candle may still be forming"
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                statusText = isSnapshot ? "Bundled historical snapshot" : "Previously fetched candles"
            } else {
                errorMessage = error.localizedDescription
                statusText = candles.isEmpty ? "No candles available" : "Refresh failed · keeping displayed candles"
            }
        }
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
        let visible = candles.suffix(visibleCandleCount)
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
        var lower = 0
        var upper = candles.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if candles[middle].timestamp < xValue { lower = middle + 1 } else { upper = middle }
        }
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

    private func replaceCandles(_ candles: [BTCCandle]) {
        self.candles = candles
        candlesByTime = Dictionary(uniqueKeysWithValues: candles.map { ($0.timestamp, $0) })
        sma = BTCIndicators.simpleMovingAverage(candles, window: 10)
        ema = BTCIndicators.exponentialMovingAverage(candles, window: 10)
        revision = UUID()
        redraw.send(())
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
