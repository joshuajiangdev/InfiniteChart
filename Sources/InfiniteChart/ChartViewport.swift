import Foundation
import CoreGraphics

/// The currently visible data coordinates and the plot's size in points.
/// X values retain the units chosen by the data provider.
public struct ChartViewport: Equatable, Sendable {
    public let visibleXRange: ClosedRange<Double>
    public let visibleYRange: ClosedRange<Double>
    public let plotSize: CGSize

    public init(visibleXRange: ClosedRange<Double>, visibleYRange: ClosedRange<Double>, plotSize: CGSize) {
        self.visibleXRange = visibleXRange
        self.visibleYRange = visibleYRange
        self.plotSize = plotSize
    }

    var dataRanges: DataRanges {
        DataRanges(
            chartXMin: visibleXRange.lowerBound,
            deltaX: visibleXRange.upperBound - visibleXRange.lowerBound,
            chartYMin: visibleYRange.lowerBound,
            deltaY: visibleYRange.upperBound - visibleYRange.lowerBound
        )
    }
}
