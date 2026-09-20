import Foundation

extension ChartDataProviderBase {
    /// Includes the nearest neighbor on either side so lines cross plot boundaries.
    /// Provider-defined spacing supports numeric, fractional, and irregular X values.
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
