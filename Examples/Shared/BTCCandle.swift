import Foundation

/// One minute of BTC/USD trading. Chart timestamps are milliseconds since 1970.
public struct BTCCandle: Equatable {
    public let timestamp: Double
    public let low: Double
    public let high: Double
    public let open: Double
    public let close: Double
    public let volume: Double
}

enum BTCCandleError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case httpStatus(Int)
    case missingSnapshot

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "Coinbase returned no candles."
        case .invalidResponse: return "Coinbase returned invalid candle data."
        case .httpStatus(let status): return "Coinbase request failed (HTTP \(status))."
        case .missingSnapshot: return "The bundled BTC/USD snapshot could not be found."
        }
    }
}

enum CoinbaseCandles {
    /// Coinbase returns [time in seconds, low, high, open, close, volume], newest first.
    static func decode(_ data: Data) throws -> [BTCCandle] {
        let rows: [[Double]]
        do {
            rows = try JSONDecoder().decode([[Double]].self, from: data)
        } catch {
            throw BTCCandleError.invalidResponse
        }
        guard !rows.isEmpty else { throw BTCCandleError.emptyResponse }

        var timestamps = Set<Double>()
        return try rows.map { row in
            guard row.count == 6, row.allSatisfy({ $0.isFinite }),
                  row[0] > 0, row[0].truncatingRemainder(dividingBy: 60) == 0,
                  (row[0] * 1_000).isFinite,
                  row[1] > 0, row[2] >= row[1],
                  (row[1]...row[2]).contains(row[3]),
                  (row[1]...row[2]).contains(row[4]), row[5] >= 0,
                  timestamps.insert(row[0]).inserted else {
                throw BTCCandleError.invalidResponse
            }
            return BTCCandle(
                timestamp: row[0] * 1_000, low: row[1], high: row[2],
                open: row[3], close: row[4], volume: row[5]
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }
}

enum BTCIndicators {
    /// A full window is required; values before the tenth candle are omitted.
    static func simpleMovingAverage(_ candles: [BTCCandle], window: Int) -> [(x: Double, y: Double)] {
        guard window > 0, candles.count >= window else { return [] }
        var sum = candles.prefix(window).reduce(0) { $0 + $1.close }
        var points = [(x: candles[window - 1].timestamp, y: sum / Double(window))]
        for index in window..<candles.count {
            sum += candles[index].close - candles[index - window].close
            points.append((x: candles[index].timestamp, y: sum / Double(window)))
        }
        return points
    }

    /// Seeds the EMA with the first full window's SMA, then uses alpha = 2 / (window + 1).
    static func exponentialMovingAverage(_ candles: [BTCCandle], window: Int) -> [(x: Double, y: Double)] {
        guard window > 0, candles.count >= window else { return [] }
        var value = candles.prefix(window).reduce(0) { $0 + $1.close } / Double(window)
        let alpha = 2 / Double(window + 1)
        var points = [(x: candles[window - 1].timestamp, y: value)]
        for candle in candles.dropFirst(window) {
            value += alpha * (candle.close - value)
            points.append((x: candle.timestamp, y: value))
        }
        return points
    }
}
