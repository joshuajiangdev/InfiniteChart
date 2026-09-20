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
    
    public init(chartXMin: Double, deltaX: Double, chartYMin: Double, deltaY: Double) {
        self.chartXMin = chartXMin
        self.deltaX = deltaX
        self.chartYMin = chartYMin
        self.deltaY = deltaY
    }
}

public protocol ChartDataProviderDelegate: AnyObject {
    func transformerDidUpdate(transformer: any Transformer)
}

public protocol ChartDataProviderBase {
    
    /// Emit after data changes. An initial event is not required.
    var redrawStream: AnyPublisher<Void, Never> { get }

    /// Legacy compatibility hook; observe the chart's viewportStream for changes.
    var tranformerUpdatedDelegate: ChartDataProviderDelegate? { get }

    /// Finite initial bounds with positive spans, or nil while data is unavailable.
    func getInitDataRanges() -> DataRanges?
    
    /**
     Find an available x value at or below/above the target.
     
     - Parameter
        to: The target value we want to find the nearest x value to
        seekBelow: true searches at or below the target; false searches at or above it
        offset: number of additional available points to move in that direction

     - Returns: A finite x value, or nil if no point is available. At a data boundary,
       implementations may return nil or clamp to the first/last point. At an exact
       match, offset 0 returns that point and offset 1 advances to its neighbor.
     */
    func getClosestXValue(to xValue: Double, seekBelow: Bool, offset: Int) -> Double?
    
    var technicalIndicators: [TechnicalIndicator] { get }
}

public extension ChartDataProviderBase {
    var tranformerUpdatedDelegate: ChartDataProviderDelegate? { nil }
    var technicalIndicators: [TechnicalIndicator] { [] }
}

public struct TechnicalIndicator {
    public let name: String
    public let color: ChartColor
    public let dataPoints: [(x: Double, y: Double)]

    public init(name: String, color: ChartColor, dataPoints: [(x: Double, y: Double)]) {
        self.name = name
        self.color = color
        self.dataPoints = dataPoints
    }
}

public protocol LineChartDataProvider: ChartDataProviderBase {
    
    /// The Y value at an available X coordinate, or nil to leave a line gap.
    func getYValue(for xValue: Double) -> Double?
}

public struct CandleStickDataPoint {
    public let high: Double
    public let low: Double
    public let open: Double
    public let close: Double
    public let color: ChartColor
    
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
    func getVolumeValueAndColor(for xValue: Double) -> (volume: Double, color: ChartColor)?
}
