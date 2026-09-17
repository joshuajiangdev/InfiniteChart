import Foundation

/// Coinbase accepts at most 300 buckets per request. Using 299 intervals leaves
/// room for either inclusive endpoint convention while pages are filtered [start, end).
struct CoinbaseHistoryRequest {
    let intervalMinutes: Int
    let coveredRange: ClosedRange<Double>
    let pages: [URLRequest]
    let pageRanges: [Range<Double>]

    init(intervalMinutes: Int, visibleRange: ClosedRange<Double>) throws {
        guard [1, 5, 15].contains(intervalMinutes),
              visibleRange.lowerBound.isFinite, visibleRange.upperBound.isFinite,
              visibleRange.lowerBound >= 0, visibleRange.lowerBound < visibleRange.upperBound else {
            throw BTCCandleError.invalidResponse
        }
        let step = Double(intervalMinutes) * 60_000
        let visibleSpan = visibleRange.upperBound - visibleRange.lowerBound
        let span = max(visibleSpan * 1.5, step * 240)
        let center = visibleRange.lowerBound + visibleSpan / 2
        let start = max(0, floor((center - span / 2) / step) * step)
        let end = max(ceil(max(center + span / 2, start + span) / step) * step,
                      floor(visibleRange.upperBound / step) * step + step)
        // At most twelve pages per snapshot and six cached snapshots bound memory.
        guard start.isFinite, end.isFinite, end > start, (end - start) / step <= 299 * 12 else {
            throw BTCCandleError.requestedRangeTooLarge
        }
        self.intervalMinutes = intervalMinutes
        coveredRange = start...end
        let formatter = ISO8601DateFormatter()
        var ranges = [Range<Double>]()
        var requests = [URLRequest]()
        var pageStart = start
        while pageStart < end {
            let pageEnd = min(end, pageStart + 299 * step)
            var components = URLComponents(string: "https://api.exchange.coinbase.com/products/BTC-USD/candles")!
            components.queryItems = [
                URLQueryItem(name: "granularity", value: String(intervalMinutes * 60)),
                URLQueryItem(name: "start", value: formatter.string(from: Date(timeIntervalSince1970: pageStart / 1_000))),
                URLQueryItem(name: "end", value: formatter.string(from: Date(timeIntervalSince1970: pageEnd / 1_000))),
            ]
            guard let url = components.url else { throw BTCCandleError.invalidResponse }
            requests.append(CoinbaseHistory.request(url: url))
            ranges.append(pageStart..<pageEnd)
            pageStart = pageEnd
        }
        pages = requests
        pageRanges = ranges
    }

    func covers(_ range: ClosedRange<Double>, interval: Int) -> Bool {
        intervalMinutes == interval && coveredRange.lowerBound <= range.lowerBound && coveredRange.upperBound > range.upperBound
    }
}

enum CoinbaseHistory {
    static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Loads server-produced OHLCV buckets. Missing buckets remain missing;
    /// records before each requested page and duplicated endpoint rows are discarded.
    static func load(
        _ plan: CoinbaseHistoryRequest,
        fetchData: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> [BTCCandle] {
        var byTime = [Double: BTCCandle]()
        let step = Double(plan.intervalMinutes) * 60_000
        for (request, range) in zip(plan.pages, plan.pageRanges) {
            try Task.checkCancellation()
            let (data, response) = try await fetchData(request)
            try Task.checkCancellation()
            try validate(response)
            for candle in try CoinbaseCandles.decode(data, allowEmpty: true, deduplicate: true) where range.contains(candle.timestamp) {
                guard candle.timestamp.truncatingRemainder(dividingBy: step) == 0 else {
                    throw BTCCandleError.invalidResponse
                }
                byTime[candle.timestamp] = candle
            }
        }
        guard !byTime.isEmpty else { throw BTCCandleError.emptyResponse }
        return byTime.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw BTCCandleError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw BTCCandleError.httpStatus(response.statusCode) }
    }
}
