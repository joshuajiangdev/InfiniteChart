import Foundation

extension ChartDataProviderBase {
    /// Traverses provider-defined X coordinates across a range without assuming spacing.
    ///
    /// Starts at or below the lower bound when available, otherwise at the first
    /// available point above it. Stops after reaching or crossing the upper bound,
    /// retaining boundary neighbors for continuous lines. Exact boundary matches
    /// do not require an extra neighbor outside the range.
    ///
    /// Traversal also stops when the provider has no successor or returns a
    /// nonfinite or nonincreasing successor, including a clamped endpoint.
    ///
    /// - Parameter range: The visible X range in the provider's data units.
    /// - Returns: Strictly increasing, finite X coordinates, or an empty array if
    ///   the range is nonfinite or the provider supplies no finite starting point.
    func renderingXValues(in range: ClosedRange<Double>) -> [Double] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              var x = getClosestXValue(to: range.lowerBound, seekBelow: true, offset: 0)
                ?? getClosestXValue(to: range.lowerBound, seekBelow: false, offset: 0),
              x.isFinite else { return [] }

        var values = [Double]()
        while true {
            values.append(x)
            guard x < range.upperBound,
                  let next = getClosestXValue(to: x, seekBelow: false, offset: 1),
                  next.isFinite, next > x else { break }
            x = next
        }
        return values
    }
}
