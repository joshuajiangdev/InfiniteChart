import Foundation

/// Shared, bounded tick generation for either axis, independent of data units.
enum AxisTicks {
    /// Returns ascending tick values with bounded counts and representable spacing.
    ///
    /// Disabled labels and invalid or degenerate ranges produce no ticks. Centered
    /// labels shift ticks by half an interval and may extend beyond the range.
    /// - Parameters:
    ///   - min: One endpoint of the data range.
    ///   - max: The other endpoint; reversed endpoints are supported.
    ///   - config: Supplies the desired label count and centering behavior.
    /// - Returns: At most 1,003 finite, distinct values.
    static func values(min: Double, max: Double, config: AxisConfig) -> [Double] {
        guard config.labelCount > 0, min.isFinite, max.isFinite else { return [] }
        let lower = Swift.min(min, max)
        let upper = Swift.max(min, max)
        let range = upper - lower
        guard range.isFinite, range > 0 else { return [] }

        // Bound native label allocation, and never step below representable precision.
        let count = Swift.min(config.labelCount, 1_000)
        let rawInterval = Swift.max(range / Double(count), Swift.max(lower.ulp, upper.ulp))
        let magnitude = pow(10, floor(log10(rawInterval)))
        var interval = rawInterval
        if magnitude.isFinite, magnitude > 0 {
            let fraction = rawInterval / magnitude
            let multiplier = fraction <= 1 ? 1.0 : fraction <= 2 ? 2.0 : fraction <= 5 ? 5.0 : 10.0
            let rounded = multiplier * magnitude
            if rounded.isFinite { interval = rounded }
        }
        guard interval.isFinite, interval > 0 else { return [] }

        let halfStep = config.centerAxisLabelsEnabled ? 0.5 : 0
        let first = ceil(lower / interval) - halfStep
        let last = floor(upper / interval) + halfStep
        guard first.isFinite, last.isFinite, last >= first else { return [] }
        let tickCount = Int(Swift.min(last - first + 1, Double(count + 3)))
        var values: [Double] = []
        for index in 0..<tickCount {
            let value = (first + Double(index)) * interval
            guard value.isFinite, values.last.map({ value > $0 }) ?? true else { continue }
            values.append(value == 0 ? 0 : value)
        }
        return values
    }
}
