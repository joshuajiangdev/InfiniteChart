import Foundation

/// An immutable set of candles and indicators at one application-selected resolution.
struct BTCDetailData {
    let candles: [BTCCandle]
    let candlesByTime: [Double: BTCCandle]
    let sma: [(x: Double, y: Double)]
    let ema: [(x: Double, y: Double)]

    init(candles: [BTCCandle]) {
        self.candles = candles
        candlesByTime = Dictionary(uniqueKeysWithValues: candles.map { ($0.timestamp, $0) })
        // Ten periods means ten displayed buckets, at whichever resolution is selected.
        sma = BTCIndicators.simpleMovingAverage(candles, window: 10)
        ema = BTCIndicators.exponentialMovingAverage(candles, window: 10)
    }
}

/// Coverage records the queried interval, including real gaps where Coinbase returned no trades.
struct BTCHistorySnapshot {
    let id = UUID()
    let intervalMinutes: Int
    let coveredRange: ClosedRange<Double>
    let data: BTCDetailData
    let isBundled: Bool
    let fetchedAt: Date

    func covers(_ range: ClosedRange<Double>, interval: Int) -> Bool {
        intervalMinutes == interval && coveredRange.lowerBound <= range.lowerBound && coveredRange.upperBound > range.upperBound
    }

    func isFresh(at now: Date) -> Bool {
        // Historical windows are immutable for this example. Windows near the live edge
        // expire so a buffered request into the future cannot permanently hide new candles.
        let liveEdge = fetchedAt.timeIntervalSince1970 * 1_000 - Double(intervalMinutes) * 120_000
        return isBundled || coveredRange.upperBound < liveEdge || now.timeIntervalSince(fetchedAt) < 60
    }
}
