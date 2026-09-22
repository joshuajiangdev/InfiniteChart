//
//  DataProvider.swift
//
//
//  Created by Joshua Jiang on 8/24/24.
//

import Foundation
import Combine

public struct DataRanges {
    public let chartXMin: Double
    public let deltaX: Double
    public let chartYMin: Double
    public let deltaY: Double
    
    /// Stores initial axis bounds in the provider's data units without validating them.
    /// The chart requires finite minima and finite, positive spans with representable upper bounds.
    public init(chartXMin: Double, deltaX: Double, chartYMin: Double, deltaY: Double) {
        self.chartXMin = chartXMin
        self.deltaX = deltaX
        self.chartYMin = chartYMin
        self.deltaY = deltaY
    }
}

public protocol ChartDataProviderBase {
    
    /// Emit after data changes. An initial event is not required.
    var redrawStream: AnyPublisher<Void, Never> { get }

    /// Finite initial bounds with positive spans, or nil while data is unavailable.
    func getInitDataRanges() -> DataRanges?
    
    /// Finds an available X coordinate in the requested direction, then advances by sample count.
    ///
    /// - Parameters:
    ///   - xValue: The target coordinate in the provider's X units.
    ///   - seekBelow: Whether to search at or below the target instead of at or above it.
    ///   - offset: Additional available samples to move in the search direction.
    ///     At an exact match, zero returns that sample and one advances to its neighbor.
    /// - Returns: A finite coordinate, or nil when no sample is available. At a data boundary,
    ///   implementations may return nil or clamp to the first or last sample.
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double?
    
    var technicalIndicators: [TechnicalIndicator] { get }
}

public extension ChartDataProviderBase {
    var technicalIndicators: [TechnicalIndicator] { [] }
}

public struct TechnicalIndicator {
    public let name: String
    public let color: ChartColor
    public let dataPoints: [(x: Double, y: Double)]

    /// Stores a precomputed indicator series in drawing order using the provider's data coordinates.
    public init(name: String, color: ChartColor, dataPoints: [(x: Double, y: Double)]) {
        self.name = name
        self.color = color
        self.dataPoints = dataPoints
    }
}

public protocol LineChartDataProvider: ChartDataProviderBase {
    
    /// Returns the Y value at an available X coordinate; nil or a nonfinite value leaves a line gap.
    func getYValue(for xValue: Double) -> Double?
}

public struct CandleStickDataPoint {
    public let high: Double
    public let low: Double
    public let open: Double
    public let close: Double
    public let color: ChartColor
    
    /// Stores a candle's OHLC values in the provider's Y units and its drawing color.
    /// The renderer skips candles containing nonfinite values.
    public init(high: Double, low: Double, open: Double, close: Double, color: ChartColor) {
        self.high = high
        self.low = low
        self.open = open
        self.close = close
        self.color = color
    }
}

public protocol CandleStickDataProvider: ChartDataProviderBase {
    
    /// The candle at an available X coordinate, or nil to omit it.
    func getCandleStickDataPoint(for xValue: Double) -> CandleStickDataPoint?
}

public protocol VolumeDataProvider: ChartDataProviderBase {
    /// Returns volume and color at an available X coordinate, or nil to omit that bar.
    /// Only finite, positive volumes inside the visible X range contribute to panel scaling.
    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)?
}
